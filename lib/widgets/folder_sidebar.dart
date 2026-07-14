import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/folder.dart';
import '../providers/email_provider.dart';
import '../providers/folder_provider.dart';
import '../theme.dart';

/// Dark ProtonMail-style sidebar: compose button, folder list, settings.
class FolderSidebar extends ConsumerWidget {
  const FolderSidebar({
    super.key,
    required this.onCompose,
    required this.onOpenSettings,
    this.onFolderSelected,
  });

  final VoidCallback onCompose;
  final VoidCallback onOpenSettings;

  /// Called after a folder tap (used to close the drawer on mobile).
  final VoidCallback? onFolderSelected;

  static (IconData, String) _iconAndLabel(Folder folder) {
    final name = folder.name.toLowerCase();
    final path = folder.path.toLowerCase();
    if (path == 'inbox') return (Icons.inbox_rounded, 'Boîte de réception');
    if (name.contains('sent') || name.contains('envoy')) {
      return (Icons.send_rounded, 'Envoyés');
    }
    if (name.contains('draft') || name.contains('brouillon')) {
      return (Icons.edit_note_rounded, 'Brouillons');
    }
    if (name.contains('trash') ||
        name.contains('corbeille') ||
        name.contains('deleted')) {
      return (Icons.delete_outline_rounded, 'Corbeille');
    }
    if (name.contains('spam') ||
        name.contains('junk') ||
        name.contains('indésirable')) {
      return (Icons.report_gmailerrorred_rounded, 'Indésirables');
    }
    if (name.contains('archive')) {
      return (Icons.archive_outlined, 'Archive');
    }
    return (Icons.folder_outlined, folder.name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(folderListProvider);
    final currentFolder = ref.watch(currentFolderProvider);

    return Container(
      color: AppColors.sidebarBackground,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Row(
                children: [
                  const Icon(Icons.mail_rounded,
                      color: AppColors.primary, size: 26),
                  const SizedBox(width: 10),
                  Text(
                    'OpenMailbox',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: onCompose,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Nouveau message'),
              ),
            ),
            Expanded(
              child: foldersAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                ),
                error: (error, _) => _SidebarError(
                  message: '$error',
                  onRetry: () =>
                      ref.read(folderListProvider.notifier).refresh(),
                ),
                data: (folders) => ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final folder in folders)
                      _FolderTile(
                        folder: folder,
                        selected: folder.path == currentFolder,
                        onTap: () {
                          ref
                              .read(currentFolderProvider.notifier)
                              .select(folder.path);
                          ref.read(emailListProvider.notifier).sync();
                          onFolderSelected?.call();
                        },
                      ),
                  ],
                ),
              ),
            ),
            const Divider(color: Colors.white12),
            ListTile(
              dense: true,
              leading: const Icon(Icons.settings_outlined,
                  color: AppColors.sidebarText, size: 20),
              title: const Text(
                'Paramètres',
                style: TextStyle(color: AppColors.sidebarText, fontSize: 14),
              ),
              onTap: onOpenSettings,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.selected,
    required this.onTap,
  });

  final Folder folder;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = FolderSidebar._iconAndLabel(folder);
    final color =
        selected ? AppColors.sidebarTextSelected : AppColors.sidebarText;
    final read = folder.total - folder.unread;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: '${folder.unread} non lu${folder.unread > 1 ? 's' : ''} · '
            '$read lu${read > 1 ? 's' : ''} · '
            '${folder.total} au total',
        waitDuration: const Duration(milliseconds: 600),
        child: Material(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.35)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 19, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (folder.total > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${folder.total}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                  if (folder.unread > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${folder.unread}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarError extends StatelessWidget {
  const _SidebarError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 32),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: const Text('Réessayer',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
