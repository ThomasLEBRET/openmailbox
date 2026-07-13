import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/email.dart';
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

  /// Connects to IMAP, pulls the latest messages for the current folder
  /// and refreshes the local cache.
  Future<void> sync() async {
    state = const AsyncLoading<List<Email>>();
    state = await AsyncValue.guard(() async {
      final folder = ref.read(currentFolderProvider);
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
        final emails = await imap.fetchRecentMessages(folder);
        await storage.saveEmails(emails);
        return emails;
      } finally {
        await imap.disconnect();
      }
    });
  }

  Future<void> markRead(int uid, bool isRead) async {
    final folder = ref.read(currentFolderProvider);
    final storage = ref.read(storageServiceProvider);
    await storage.setRead(folder, uid, isRead);
    state = state.whenData(
      (emails) => [
        for (final email in emails)
          if (email.uid == uid) email.copyWith(isRead: isRead) else email,
      ],
    );
  }

  Future<void> deleteEmail(int uid) async {
    final folder = ref.read(currentFolderProvider);
    final storage = ref.read(storageServiceProvider);
    await storage.deleteEmail(folder, uid);
    state = state.whenData(
      (emails) => emails.where((email) => email.uid != uid).toList(),
    );
  }
}

final emailListProvider =
    AsyncNotifierProvider<EmailListNotifier, List<Email>>(
  EmailListNotifier.new,
);
