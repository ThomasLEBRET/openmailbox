import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'imap_service.dart';
import 'notification_service.dart';
import 'storage_service.dart';

const _taskName = 'checkNewMail';
const _taskUnique = 'openmailbox.checkNewMail';

/// Registers a periodic background check (Android). Android caps the
/// frequency at ~15 min, so this is "near real-time", not instant — a
/// truly instant push would need a server holding an IMAP IDLE
/// connection. macOS has no equivalent here; its in-app watcher covers
/// the window while the app runs.
Future<void> initBackgroundMailCheck() async {
  if (!Platform.isAndroid) return;
  try {
    await Workmanager().initialize(backgroundCallback);
    await Workmanager().registerPeriodicTask(
      _taskUnique,
      _taskName,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } catch (_) {
    // Background scheduling unavailable — the in-app watcher still runs.
  }
}

/// Runs in a separate background isolate: no Riverpod, no UI. It rebuilds
/// the services it needs, checks the unread total across all folders of
/// the active account, and notifies when it grew since the last run.
@pragma('vm:entry-point')
void backgroundCallback() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final storage = StorageService();
      final account = (await storage.loadAccounts()).current;
      if (account == null) return true;
      final password = await storage.readImapPassword(account.id);
      if (password == null) return true;

      final imap = ImapService();
      await imap.ensureConnected(account.config.imap, password);
      final int total;
      try {
        final folders = await imap.listFolders();
        total = folders.fold<int>(0, (sum, folder) => sum + folder.unread);
      } finally {
        await imap.disconnect();
      }

      final last = await storage.readLastUnread();
      if (last >= 0 && total > last) {
        await NotificationService.init();
        await NotificationService.notifyNewMail(total - last, total);
      }
      await storage.writeLastUnread(total);
      return true;
    } catch (_) {
      // Never throw from a worker: it would trigger OS retry storms.
      return true;
    }
  });
}
