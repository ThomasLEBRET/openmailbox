import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/folder.dart';
import '../services/imap_service.dart';
import 'config_provider.dart';

final imapServiceProvider = Provider<ImapService>((ref) => ImapService());

/// Currently selected folder path (defaults to INBOX).
class CurrentFolderNotifier extends Notifier<String> {
  @override
  String build() => 'INBOX';

  void select(String path) => state = path;
}

final currentFolderProvider =
    NotifierProvider<CurrentFolderNotifier, String>(CurrentFolderNotifier.new);

class FolderListNotifier extends AsyncNotifier<List<Folder>> {
  @override
  Future<List<Folder>> build() async {
    final storage = ref.read(storageServiceProvider);
    return storage.loadFolders();
  }

  /// Connects to IMAP, re-lists folders and refreshes the local cache.
  Future<void> refresh() async {
    state = const AsyncLoading<List<Folder>>();
    state = await AsyncValue.guard(() async {
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
        final folders = await imap.listFolders();
        await storage.saveFolders(folders);
        return folders;
      } finally {
        await imap.disconnect();
      }
    });
  }
}

final folderListProvider =
    AsyncNotifierProvider<FolderListNotifier, List<Folder>>(
  FolderListNotifier.new,
);
