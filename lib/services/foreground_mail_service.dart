import 'dart:async';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'notification_service.dart';
import 'storage_service.dart';

/// "Instant" new-mail notifications on Android via a foreground service that
/// holds an IMAP IDLE connection open (like Thunderbird/K-9 on desktop).
///
/// This is the opt-in background mechanism: IDLE lets the server push as soon
/// as mail lands, but the OS only permits a persistent connection from a
/// *foreground* service, which comes with an always-visible notification.
/// When off, new mail only surfaces while the app is open. (A WorkManager
/// periodic poll used to cover the "app closed" case, but its native
/// auto-init crashed the app at startup, so it was removed.)
///
/// Every native touch-point is guarded: a plugin failure here must never
/// take the app down (a plugin crash at startup already did once).

const _fgChannelId = 'om_watcher';
const _fgChannelName = 'Surveillance des messages';

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
            'Maintient la connexion pour les notifications instantanées.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Heartbeat: reconnect if IDLE dropped. Not the mail-check itself —
        // that is push-driven by the server over IDLE.
        eventAction: ForegroundTaskEventAction.repeat(5 * 60 * 1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  } catch (_) {
    // Foreground-task plumbing unavailable — instant mode just won't start.
  }
}

/// Starts the IDLE watcher. No-op off Android, if already running, or if the
/// notification permission is missing (a FGS with a hidden notification is
/// killed by the OS).
Future<void> startMailWatcher() async {
  if (!Platform.isAndroid) return;
  try {
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId: 42,
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: 'OpenMailbox',
      notificationText: 'Surveillance de la boîte de réception',
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
  MailClient? _client;
  bool _connecting = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();
    await _connect();
  }

  /// Reconnects and re-arms IDLE. Serialized via [_connecting] so the
  /// heartbeat can't stack a second connection on top of a live one.
  Future<void> _connect() async {
    if (_connecting) return;
    _connecting = true;
    try {
      await _client?.disconnect();
      _client = null;

      final storage = StorageService();
      final account = (await storage.loadAccounts()).current;
      if (account == null) return;
      final password = await storage.readImapPassword(account.id);
      if (password == null) return;

      final imap = account.config.imap;
      final smtp = account.config.smtp;
      final mailAccount = MailAccount.fromManualSettings(
        name: 'openmailbox',
        email: imap.username,
        userName: imap.username,
        loginName: imap.username,
        password: password,
        incomingHost: imap.host,
        incomingPort: imap.port,
        outgoingHost: smtp.host,
        outgoingPort: smtp.port,
      );

      final client = MailClient(mailAccount, isLogEnabled: false);
      await client.connect();
      await client.selectInbox();
      await NotificationService.init();

      // A new message landing in INBOX fires MailLoadEvent while IDLE is on.
      client.eventBus.on<MailLoadEvent>().listen((event) {
        final unread = client.selectedMailbox?.messagesUnseen ?? 1;
        NotificationService.notifyNewMail(1, unread <= 0 ? 1 : unread);
      });

      // startPolling uses IMAP IDLE where the server supports it (Mailo
      // does), otherwise a NOOP poll — either way MailLoadEvent fires.
      await client.startPolling();
      _client = client;
    } catch (_) {
      // Leave _client null; the next heartbeat retries.
      _client = null;
    } finally {
      _connecting = false;
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    final client = _client;
    if (client == null || !client.isConnected) {
      _connect();
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    try {
      await _client?.disconnect();
    } catch (_) {}
    _client = null;
  }
}
