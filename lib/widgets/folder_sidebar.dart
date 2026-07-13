import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/email_provider.dart';
import '../providers/folder_provider.dart';

class FolderSidebar extends ConsumerWidget {
  const FolderSidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(folderListProvider);
    final currentFolder = ref.watch(currentFolderProvider);

    return foldersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Erreur: $error')),
      data: (folders) {
        return ListView.builder(
          itemCount: folders.length,
          itemBuilder: (context, index) {
            final folder = folders[index];
            return ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(folder.name),
              selected: folder.path == currentFolder,
              onTap: () {
                ref.read(currentFolderProvider.notifier).select(folder.path);
                ref.read(emailListProvider.notifier).sync();
              },
            );
          },
        );
      },
    );
  }
}
