import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/notification_service.dart';
import 'config_provider.dart';
import 'folder_provider.dart';

/// Every 3 minutes, refreshes all folder counts (which also updates the
/// sidebar badges and the app-icon badge) and raises a native
/// notification when the total unread across ALL folders grows.
/// Active while the app runs; read it once (e.g. from the home screen).
final inboxWatcherProvider = Provider<void>((ref) {
  var lastTotal = -1;

  int totalUnread() => (ref.read(folderListProvider).value ?? const [])
      .fold<int>(0, (sum, folder) => sum + folder.unread);

  Future<void> check() async {
    if (ref.read(currentAccountProvider) == null) return;
    try {
      await ref.read(folderListProvider.notifier).refresh();
      final total = totalUnread();
      if (lastTotal >= 0 && total > lastTotal) {
        await NotificationService.notifyNewMail(total - lastTotal, total);
      }
      lastTotal = total;
    } catch (_) {
      // Offline or busy — try again on the next tick.
    }
  }

  final timer = Timer.periodic(const Duration(minutes: 3), (_) => check());
  Future.microtask(check);
  ref.onDispose(timer.cancel);
});
