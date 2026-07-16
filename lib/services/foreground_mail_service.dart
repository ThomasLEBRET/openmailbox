import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'imap_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';

/// Background new-mail notifications on Android via a foreground service.
///
/// It scans **every folder's** unread count on a short interval and notifies
/// when any folder grows — not just INBOX. This matters because server-side
/// filters often deliver mail straight into sub-folders, bypassing INBOX
/// entirely; an INBOX-only IMAP IDLE would never see those (and did not).
///
/// A foreground service is the only way Android lets an app keep polling
/// while closed, hence the persistent notification. It's opt-in
/// ([AppPrefs.instantNotifications]); off, new mail only surfaces while the
/// app is open. (A WorkManager 15-min poll used to cover the closed case but
/// its native auto-init crashed the app at startup, so it was removed.)
///
/// Every native touch-point is guarded — a plugin failure here must never
/// take the app down.

const _fgChannelId = 'om_watcher';
const _fgChannelName = 'Surveillance des messages';

/// How often the watcher re-scans all folders. The foreground service stays
/// alive continuously, so this can be far tighter than WorkManager's 15-min
/// floor — new mail in any folder surfaces within roughly this window.
const _scanInterval = Duration(seconds: 60);

/// Registers the foreground-task channel + options. Cheap, idempotent, and
/// does not start anything — safe to call at every startup.
void initForegroundTask() {
  if (!Platform.isAndroid) return;
  try {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _fgChannelId,
        channelName: _fgChannelName,
        channelDescription:
            'Vérifie l\'arrivée de nouveaux messages en arrière-plan.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // The scan itself runs on our own Timer; this is just a coarse
        // safety heartbeat that re-arms it if the isolate was frozen.
        eventAction: ForegroundTaskEventAction.repeat(5 * 60 * 1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  } catch (_) {
    // Foreground-task plumbing unavailable — background mode just won't start.
  }
}

/// Starts the watcher. No-op off Android or if already running.
Future<void> startMailWatcher() async {
  if (!Platform.isAndroid) return;
  try {
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId: 42,
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: 'OpenMailbox',
      notificationText: 'Surveillance de vos dossiers',
      callback: startMailWatcherCallback,
    );
  } catch (_) {
    // Best-effort.
  }
}

Future<void> stopMailWatcher() async {
  if (!Platform.isAndroid) return;
  try {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  } catch (_) {}
}

/// Entry point of the foreground isolate. Must be top-level + vm:entry-point.
@pragma('vm:entry-point')
void startMailWatcherCallback() {
  FlutterForegroundTask.setTaskHandler(_MailWatcherHandler());
}

class _MailWatcherHandler extends TaskHandler {
  final _imap = ImapService();
  final _storage = StorageService();
  Timer? _timer;
  bool _scanning = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();
    await NotificationService.init();
    // First scan establishes the baseline (no notification); then poll.
    await _scan();
    _timer = Timer.periodic(_scanInterval, (_) => _scan());
  }

  Future<void> _scan() async {
    if (_scanning) return; // A slow scan must not overlap the next tick.
    _scanning = true;
    try {
      final account = (await _storage.loadAccounts()).current;
      if (account == null) return;
      final password = await _storage.readImapPassword(account.id);
      if (password == null) return;

      await _imap.ensureConnected(account.config.imap, password);
      final folders = await _imap.runExclusive(_imap.listFolders);

      final current = <String, int>{
        for (final folder in folders) folder.path: folder.unread,
      };
      final baseline = await _storage.readFolderUnread();

      // Sum the growth across folders we've already seen. A folder absent
      // from the baseline (first run, or newly created) is recorded but
      // never notified, so we don't announce the whole mailbox at once.
      var newCount = 0;
      for (final entry in current.entries) {
        final previous = baseline[entry.key];
        if (previous != null && entry.value > previous) {
          newCount += entry.value - previous;
        }
      }
      final totalUnread =
          current.values.fold<int>(0, (sum, value) => sum + value);

      await _storage.writeFolderUnread(current);
      if (newCount > 0) {
        await NotificationService.notifyNewMail(newCount, totalUnread);
      }
    } catch (_) {
      // Network hiccup or dead session: drop the connection so the next
      // scan reconnects cleanly. Never throw from here.
      _imap.reset();
    } finally {
      _scanning = false;
    }
  }

  /// Coarse heartbeat: if our Timer somehow died (isolate frozen/resumed),
  /// bring it back.
  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_timer == null || !_timer!.isActive) {
      _timer = Timer.periodic(_scanInterval, (_) => _scan());
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _timer?.cancel();
    _timer = null;
    try {
      await _imap.disconnect();
    } catch (_) {}
  }
}
