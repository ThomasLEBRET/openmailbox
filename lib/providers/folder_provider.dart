import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/folder.dart';
import 'config_provider.dart';
import 'imap_session.dart';

/// Currently selected folder path (defaults to INBOX).
/// Watching the active account resets it to INBOX on account switch.
class CurrentFolderNotifier extends Notifier<String> {
  @override
  String build() {
    ref.watch(currentAccountProvider.select((account) => account?.id));
    return 'INBOX';
  }

  void select(String path) => state = path;
}

final currentFolderProvider =
    NotifierProvider<CurrentFolderNotifier, String>(CurrentFolderNotifier.new);

/// Best-effort trash folder path. Prefers the server's lowercase system
/// folder when several trash-like folders exist (Mailo has both "trash"
/// and a user-created "Trash").
String? findTrashPath(List<Folder> folders) {
  Folder? byName;
  for (final folder in folders) {
    if (folder.path == 'trash') return folder.path;
    final name = folder.name.toLowerCase();
    if (folder.path.toLowerCase() == 'trash' ||
        name.contains('trash') ||
        name.contains('corbeille') ||
        name.contains('deleted')) {
      byName ??= folder;
    }
  }
  return byName?.path;
}

class FolderListNotifier extends AsyncNotifier<List<Folder>> {
  @override
  Future<List<Folder>> build() async {
    final account = ref.watch(currentAccountProvider);
    if (account == null) return const [];
    final storage = ref.read(storageServiceProvider);
    return storage.loadFolders(account.id);
  }

  /// Re-lists folders (with STATUS counts) and refreshes the local cache.
  /// The sidebar keeps showing the current list while this runs; a
  /// transient failure keeps it too (badges catch up on the next pass).
  Future<void> refresh() async {
    final account = ref.read(currentAccountProvider);
    if (account == null) return;
    final result = await AsyncValue.guard(() async {
      final folders = await withImapSession(
          ref, (imap) => imap.listFolders(),
          background: true);
      await ref
          .read(storageServiceProvider)
          .saveFolders(account.id, folders);
      return folders;
    });
    // Ignore a stale result after an account switch, and keep the sidebar
    // populated on transient failures.
    if (ref.read(currentAccountProvider)?.id != account.id) return;
    if (result.hasError && (state.value?.isNotEmpty ?? false)) {
      return;
    }
    state = result;
  }

  Future<void> createFolder(String name) async {
    await withImapSession(ref, (imap) => imap.createFolder(name));
    await refresh();
  }

  Future<void> renameFolder(String path, String newName) async {
    await withImapSession(ref, (imap) => imap.renameFolder(path, newName));
    if (ref.read(currentFolderProvider) == path) {
      ref.read(currentFolderProvider.notifier).select('INBOX');
    }
    await refresh();
  }

  Future<void> deleteFolder(String path) async {
    await withImapSession(ref, (imap) => imap.deleteFolder(path));
    final account = ref.read(currentAccountProvider);
    if (account != null) {
      // Purge the cached emails of the removed folder.
      await ref.read(storageServiceProvider).deleteAccountFolder(
          account.id, path);
    }
    if (ref.read(currentFolderProvider) == path) {
      ref.read(currentFolderProvider.notifier).select('INBOX');
    }
    await refresh();
  }

  /// Optimistically shifts the counts of [path] (e.g. unread -1 when an
  /// email is read locally) so badges stay coherent between two syncs.
  Future<void> adjustCounts(String path,
      {int unreadDelta = 0, int totalDelta = 0}) async {
    final current = state.value;
    final account = ref.read(currentAccountProvider);
    if (current == null || account == null) return;
    final updated = [
      for (final folder in current)
        if (folder.path == path)
          folder.copyWith(
            unread: (folder.unread + unreadDelta).clamp(0, 1 << 31),
            total: (folder.total + totalDelta).clamp(0, 1 << 31),
          )
        else
          folder,
    ];
    state = AsyncData(updated);
    await ref.read(storageServiceProvider).saveFolders(account.id, updated);
  }
}

final folderListProvider =
    AsyncNotifierProvider<FolderListNotifier, List<Folder>>(
  FolderListNotifier.new,
);
