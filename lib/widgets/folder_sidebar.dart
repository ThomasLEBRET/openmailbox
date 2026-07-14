import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/folder.dart';
import '../providers/config_provider.dart';
import '../providers/email_provider.dart';
import '../providers/folder_provider.dart';
import '../theme.dart';

/// Dark ProtonMail-style sidebar: compose button, folder list, settings.
///
/// Each system role (inbox, sent, trash…) is assigned to at most ONE
/// folder — an account can hold both the server's `trash` and a custom
/// `Trash` folder; only the system one gets the French label, the other
/// keeps its own name so the two stay distinguishable.
class FolderSidebar extends ConsumerWidget {
  const FolderSidebar({
    super.key,
    required this.onCompose,
    required this.onOpenSettings,
    required this.onAddAccount,
    this.onOpenAppearance,
    this.onFolderSelected,
  });

  final VoidCallback onCompose;
  final VoidCallback onOpenSettings;
  final VoidCallback onAddAccount;
  final VoidCallback? onOpenAppearance;

  /// Called after a folder tap (used to close the drawer on mobile).
  final VoidCallback? onFolderSelected;

  static String? _findRole(List<Folder> folders, List<String> keywords,
      Set<String> claimed) {
    // Exact lowercase path match first (server system folders), then
    // name heuristics (Gmail-style "[Gmail]/Sent Mail").
    for (final folder in folders) {
      if (claimed.contains(folder.path)) continue;
      if (keywords.contains(folder.path.toLowerCase())) return folder.path;
    }
    for (final folder in folders) {
      if (claimed.contains(folder.path)) continue;
      final name = folder.name.toLowerCase();
      if (keywords.any(name.contains)) return folder.path;
    }
    return null;
  }

  /// path → (icon, label, rank) for system folders.
  static Map<String, (IconData, String, int)> _systemRoles(
      List<Folder> folders) {
    final result = <String, (IconData, String, int)>{};
    final claimed = <String>{};

    void assign(String? path, IconData icon, String label, int rank) {
      if (path == null) return;
      result[path] = (icon, label, rank);
      claimed.add(path);
    }

    assign(
      folders
          .where((f) => f.path.toUpperCase() == 'INBOX')
          .firstOrNull
          ?.path,
      Icons.inbox_rounded,
      'Boîte de réception',
      0,
    );
    claimed.addAll(result.keys);
    assign(_findRole(folders, ['draftbox', 'drafts', 'draft', 'brouillon'], claimed),
        Icons.edit_note_rounded, 'Brouillons', 1);
    assign(_findRole(folders, ['sent', 'envoy'], claimed),
        Icons.send_rounded, 'Envoyés', 2);
    assign(_findRole(folders, ['unsolbox', 'spam', 'junk', 'indésirable'], claimed),
        Icons.report_gmailerrorred_rounded, 'Indésirables', 3);
    assign(findTrashPath(folders), Icons.delete_outline_rounded, 'Corbeille', 4);
    assign(_findRole(folders, ['archive'], claimed),
        Icons.archive_outlined, 'Archive', 5);
    return result;
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
            _AccountSwitcher(onAddAccount: onAddAccount),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: onCompose,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentOf(context),
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
                data: (folders) {
                  final roles = _systemRoles(folders);
                  final system = folders
                      .where((f) => roles.containsKey(f.path))
                      .toList()
                    ..sort((a, b) =>
                        roles[a.path]!.$3.compareTo(roles[b.path]!.$3));
                  final custom = folders
                      .where((f) => !roles.containsKey(f.path))
                      .toList()
                    ..sort((a, b) => a.name
                        .toLowerCase()
                        .compareTo(b.name.toLowerCase()));

                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final folder in system)
                        _FolderTile(
                          folder: folder,
                          icon: roles[folder.path]!.$1,
                          label: roles[folder.path]!.$2,
                          selected: folder.path == currentFolder,
                          onTap: () => _selectFolder(ref, folder.path),
                        ),
                      if (custom.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(12, 16, 12, 6),
                          child: Text(
                            'DOSSIERS',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10.5,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        for (final folder in custom)
                          _FolderTile(
                            folder: folder,
                            icon: Icons.folder_outlined,
                            label: folder.name,
                            selected: folder.path == currentFolder,
                            onTap: () => _selectFolder(ref, folder.path),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
            const Divider(color: Colors.white12),
            ListTile(
              dense: true,
              leading: const Icon(Icons.palette_outlined,
                  color: AppColors.sidebarText, size: 20),
              title: const Text(
                'Apparence',
                style: TextStyle(color: AppColors.sidebarText, fontSize: 14),
              ),
              onTap: onOpenAppearance,
            ),
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

  void _selectFolder(WidgetRef ref, String path) {
    ref.read(currentFolderProvider.notifier).select(path);
    ref.read(emailListProvider.notifier).sync();
    onFolderSelected?.call();
  }
}

/// Current account chip with a menu to switch or add accounts.
class _AccountSwitcher extends ConsumerWidget {
  const _AccountSwitcher({required this.onAddAccount});

  final VoidCallback onAddAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsState = ref.watch(accountsProvider).value;
    final current = accountsState?.current;
    if (current == null) return const SizedBox.shrink();
    final accounts = accountsState!.accounts;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: PopupMenuButton<String>(
        tooltip: 'Changer de compte',
        offset: const Offset(0, 42),
        onSelected: (value) async {
          if (value == '_add') {
            onAddAccount();
            return;
          }
          await ref.read(accountsProvider.notifier).switchTo(value);
          // Fresh data for the newly selected account.
          ref.read(emailListProvider.notifier).sync();
          ref.read(folderListProvider.notifier).refresh();
        },
        itemBuilder: (context) => [
          for (final account in accounts)
            PopupMenuItem(
              value: account.id,
              child: Row(
                children: [
                  Icon(
                    account.id == current.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 16,
                    color: account.id == current.id
                        ? AppColors.accentOf(context)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(account.label,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: '_add',
            child: Row(
              children: [
                Icon(Icons.add, size: 16),
                SizedBox(width: 8),
                Text('Ajouter un compte'),
              ],
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: AppColors.avatarColorFor(current.label),
                child: Text(
                  current.label.isEmpty
                      ? '?'
                      : current.label[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  current.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.sidebarText,
                    fontSize: 12,
                  ),
                ),
              ),
              const Icon(Icons.unfold_more_rounded,
                  size: 15, color: AppColors.sidebarText),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Folder folder;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              ? AppColors.accentOf(context).withValues(alpha: 0.35)
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
                        color: AppColors.accentOf(context),
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
