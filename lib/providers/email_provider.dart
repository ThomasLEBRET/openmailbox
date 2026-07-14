import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/email.dart';
import '../services/imap_service.dart';
import 'config_provider.dart';
import 'folder_provider.dart';

/// Email list for the currently selected folder ([currentFolderProvider]).
class EmailListNotifier extends AsyncNotifier<List<Email>> {
  @override
  Future<List<Email>> build() async {
    final folder = ref.watch(currentFolderProvider);
    final storage = ref.read(storageServiceProvider);
    return storage.loadEmails(folder);
  }

  /// Opens an IMAP session, runs [action], always disconnects.
  Future<T> _withImap<T>(Future<T> Function(ImapService imap) action) async {
    final config = ref.read(accountConfigProvider).value;
    if (config == null) {
      throw StateError('Aucun compte configuré');
    }
    final storage = ref.read(storageServiceProvider);
    final password = await storage.readImapPassword();
    if (password == null) {
      throw StateError(
        'Mot de passe IMAP introuvable dans le trousseau (Keychain). '
        'Reconfigure le compte depuis les réglages.',
      );
    }
    final imap = ref.read(imapServiceProvider);
    await imap.connect(config.imap, password);
    try {
      return await action(imap);
    } finally {
      await imap.disconnect();
    }
  }

  /// Connects to IMAP, pulls the latest messages for the current folder
  /// and refreshes the local cache.
  Future<void> sync() async {
    state = const AsyncLoading<List<Email>>();
    state = await AsyncValue.guard(() async {
      final folder = ref.read(currentFolderProvider);
      final storage = ref.read(storageServiceProvider);
      final emails =
          await _withImap((imap) => imap.fetchRecentMessages(folder));
      await storage.saveEmails(emails);
      return emails;
    });
  }

  /// Marks locally (snappy UI), then pushes the \Seen flag to the server
  /// best-effort — the next sync reconciles if it fails.
  Future<void> markRead(int uid, bool isRead) async {
    final folder = ref.read(currentFolderProvider);
    final storage = ref.read(storageServiceProvider);
    final previous = state.value
        ?.where((email) => email.uid == uid)
        .firstOrNull
        ?.isRead;
    await storage.setRead(folder, uid, isRead);
    state = state.whenData(
      (emails) => [
        for (final email in emails)
          if (email.uid == uid) email.copyWith(isRead: isRead) else email,
      ],
    );
    if (previous != null && previous != isRead) {
      await ref
          .read(folderListProvider.notifier)
          .adjustCounts(folder, unreadDelta: isRead ? -1 : 1);
    }
    try {
      await _withImap(
          (imap) => imap.markSeen(folder, uid, isSeen: isRead));
    } catch (_) {
      // Best-effort; local state stays, next sync reconciles.
    }
  }

  /// Deletes on the server first (throws on failure so the caller can
  /// surface it), then locally.
  Future<void> deleteEmail(int uid) async {
    final folder = ref.read(currentFolderProvider);
    final storage = ref.read(storageServiceProvider);
    final wasUnread = state.value
            ?.where((email) => email.uid == uid)
            .firstOrNull
            ?.isRead ==
        false;

    await _withImap((imap) => imap.deleteMessage(folder, uid));

    await storage.deleteEmail(folder, uid);
    state = state.whenData(
      (emails) => emails.where((email) => email.uid != uid).toList(),
    );
    await ref.read(folderListProvider.notifier).adjustCounts(
          folder,
          totalDelta: -1,
          unreadDelta: wasUnread ? -1 : 0,
        );
  }
}

final emailListProvider =
    AsyncNotifierProvider<EmailListNotifier, List<Email>>(
  EmailListNotifier.new,
);
