import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/notification_service.dart';
import 'config_provider.dart';
import 'folder_provider.dart';
import 'imap_session.dart';

/// Polls the INBOX unseen count on the background connection and raises
/// a native notification (+ badge) when it grows. Active while the app
/// runs; read it once (e.g. from the home screen) to start it.
final inboxWatcherProvider = Provider<void>((ref) {
  var lastUnseen = -1;

  Future<void> check() async {
    if (ref.read(currentAccountProvider) == null) return;
    try {
      final unseen = await withImapSession(
          ref, (imap) => imap.inboxUnseenCount(),
          background: true);
      if (lastUnseen >= 0 && unseen > lastUnseen) {
        await NotificationService.notifyNewMail(
            unseen - lastUnseen, unseen);
        // Refresh the sidebar counters too.
        ref.read(folderListProvider.notifier).refresh();
      }
      lastUnseen = unseen;
    } catch (_) {
      // Offline or busy — try again on the next tick.
    }
  }

  final timer = Timer.periodic(const Duration(minutes: 3), (_) => check());
  Future.microtask(check);
  ref.onDispose(timer.cancel);
});
