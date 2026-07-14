import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/folder.dart';
import 'config_provider.dart';
import 'imap_session.dart';

/// Currently selected folder path (defaults to INBOX).
class CurrentFolderNotifier extends Notifier<String> {
  @override
  String build() => 'INBOX';

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
    final storage = ref.read(storageServiceProvider);
    return storage.loadFolders();
  }

  /// Re-lists folders (with STATUS counts) and refreshes the local cache.
  Future<void> refresh() async {
    state = const AsyncLoading<List<Folder>>();
    state = await AsyncValue.guard(() async {
      final folders =
          await withImapSession(ref, (imap) => imap.listFolders());
      await ref.read(storageServiceProvider).saveFolders(folders);
      return folders;
    });
  }

  /// Optimistically shifts the counts of [path] (e.g. unread -1 when an
  /// email is read locally) so badges stay coherent between two syncs.
  Future<void> adjustCounts(String path,
      {int unreadDelta = 0, int totalDelta = 0}) async {
    final current = state.value;
    if (current == null) return;
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
    await ref.read(storageServiceProvider).saveFolders(updated);
  }
}

final folderListProvider =
    AsyncNotifierProvider<FolderListNotifier, List<Folder>>(
  FolderListNotifier.new,
);
