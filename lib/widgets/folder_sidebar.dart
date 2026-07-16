import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/email.dart';
import '../models/folder.dart';
import '../providers/config_provider.dart';
import '../providers/email_provider.dart';
import '../providers/folder_provider.dart';
import '../models/prefs.dart';
import '../providers/prefs_provider.dart';
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
    this.onSync,
    this.onFolderSelected,
  });

  final VoidCallback onCompose;
  final VoidCallback onOpenSettings;
  final VoidCallback onAddAccount;
  final VoidCallback? onOpenAppearance;
  final VoidCallback? onSync;

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
    final side = AppColors.sidebarOf(context);

    return Container(
      color: side.bg,
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
                          color: side.textSelected,
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
                loading: () => Center(
                  child: CircularProgressIndicator(color: side.muted),
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
                          onAcceptEmail: (email) =>
                              _moveEmail(context, ref, email, folder.path),
                          onContextMenu: (position) => _folderMenu(
                              context, ref, folder.path, position,
                              isSystem: true),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 4, 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'DOSSIERS',
                                style: TextStyle(
                                  color: side.muted,
                                  fontSize: 10.5,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Nouveau dossier',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.create_new_folder_outlined,
                                  size: 17, color: side.muted),
                              onPressed: () => _createFolder(context, ref),
                            ),
                          ],
                        ),
                      ),
                      if (custom.isNotEmpty) ...[
                        for (final folder in custom)
                          _FolderTile(
                            folder: folder,
                            icon: Icons.folder_outlined,
                            label: folder.name,
                            selected: folder.path == currentFolder,
                            onTap: () => _selectFolder(ref, folder.path),
                            onAcceptEmail: (email) =>
                                _moveEmail(context, ref, email, folder.path),
                            onContextMenu: (position) => _folderMenu(
                                context, ref, folder.path, position,
                                isSystem: false),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
            Divider(color: side.divider),
            if (onSync != null)
              ListTile(
                dense: true,
                leading: Icon(Icons.sync_rounded, color: side.text, size: 20),
                title: Text(
                  'Synchroniser',
                  style: TextStyle(color: side.text, fontSize: 14),
                ),
                onTap: onSync,
              ),
            ListTile(
              dense: true,
              leading: Icon(Icons.tune_rounded, color: side.text, size: 20),
              title: Text(
                'Préférences',
                style: TextStyle(color: side.text, fontSize: 14),
              ),
              onTap: onOpenAppearance,
            ),
            ListTile(
              dense: true,
              leading: Icon(Icons.manage_accounts_outlined,
                  color: side.text, size: 20),
              title: Text(
                'Compte',
                style: TextStyle(color: side.text, fontSize: 14),
              ),
              onTap: onOpenSettings,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _moveEmail(
      BuildContext context, WidgetRef ref, Email email, String target) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(emailListProvider.notifier)
          .moveToFolder(email.uid, target);
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('Déplacé vers $target — ⌘Z pour annuler'),
          behavior: SnackBarBehavior.floating,
          width: 420,
          duration: const Duration(seconds: 3),
        ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Échec du déplacement : $e'),
        behavior: SnackBarBehavior.floating,
        width: 420,
      ));
    }
  }

  Future<void> _createFolder(BuildContext context, WidgetRef ref) async {
    final name = await _promptText(
      context,
      title: 'Nouveau dossier',
      hint: 'Nom du dossier',
      confirmLabel: 'Créer',
    );
    if (name == null || name.trim().isEmpty) return;
    try {
      await ref.read(folderListProvider.notifier).createFolder(name.trim());
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec de la création : $e')),
        );
      }
    }
  }

  /// Compact prompt dialog: 360px, title row with a close cross,
  /// Enter submits.
  Future<String?> _promptText(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    String hint = '',
    String initial = '',
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 10, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Fermer',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: hint,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onSubmitted: (value) => Navigator.of(context).pop(value),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(controller.text),
                    child: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _folderMenu(BuildContext context, WidgetRef ref, String path,
      Offset position,
      {required bool isSystem}) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      items: [
        const PopupMenuItem(value: 'color', child: Text('Couleur…')),
        if (!isSystem) ...[
          const PopupMenuItem(value: 'rename', child: Text('Renommer…')),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ],
    );
    if (action == null || !context.mounted) return;

    switch (action) {
      case 'color':
        await _pickFolderColor(context, ref, path);
      case 'rename':
        await _renameFolder(context, ref, path);
      case 'delete':
        await _deleteFolder(context, ref, path);
    }
  }

  Future<void> _pickFolderColor(
      BuildContext context, WidgetRef ref, String path) async {
    final current =
        ref.read(prefsProvider).value?.folderColors[path];
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 10, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Couleur du dossier',
                        style: TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Fermer',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (name, value) in accentChoices)
                      Tooltip(
                        message: name,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.of(context).pop(value),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Color(value),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: current == value
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(0),
                  child: const Text('Par défaut',
                      style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == null) return;
    await ref
        .read(prefsProvider.notifier)
        .setFolderColor(path, picked == 0 ? null : picked);
  }

  Future<void> _renameFolder(
      BuildContext context, WidgetRef ref, String path) async {
    final name = await _promptText(
      context,
      title: 'Renommer le dossier',
      initial: path.split('/').last,
      confirmLabel: 'Renommer',
    );
    if (name == null || name.trim().isEmpty || name.trim() == path) return;
    try {
      await ref
          .read(folderListProvider.notifier)
          .renameFolder(path, name.trim());
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec du renommage : $e')),
        );
      }
    }
  }

  Future<void> _deleteFolder(
      BuildContext context, WidgetRef ref, String path) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer « ${path.split('/').last} » ?'),
        content: const Text(
            'Le dossier et les emails qu\'il contient seront supprimés '
            'sur le serveur.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(folderListProvider.notifier).deleteFolder(path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Échec de la suppression : $e')),
        );
      }
    }
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

    final side = AppColors.sidebarOf(context);
    final accent = AppColors.accentOf(context);

    Widget avatarFor(String label, {double radius = 10}) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.avatarColorFor(label),
        child: Text(
          label.isEmpty ? '?' : label[0].toUpperCase(),
          style: TextStyle(
            fontSize: radius,
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: PopupMenuButton<String>(
          tooltip: 'Changer de compte',
          offset: const Offset(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
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
                    avatarFor(account.label, radius: 12),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        account.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: account.id == current.id
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (account.id == current.id) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check_rounded, size: 16, color: accent),
                    ],
                  ],
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: '_add',
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: accent.withValues(alpha: 0.6)),
                    ),
                    child: Icon(Icons.add, size: 15, color: accent),
                  ),
                  const SizedBox(width: 10),
                  const Text('Ajouter un compte',
                      style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: side.chip,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                avatarFor(current.label),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    current.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: side.text, fontSize: 12),
                  ),
                ),
                Icon(Icons.expand_more_rounded, size: 16, color: side.text),
              ],
            ),
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
    this.onAcceptEmail,
    this.onContextMenu,
  });

  final Folder folder;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Email>? onAcceptEmail;
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final side = AppColors.sidebarOf(context);
    final color = selected ? side.textSelected : side.text;
    final read = folder.total - folder.unread;

    return DragTarget<Email>(
      onWillAcceptWithDetails: (details) =>
          onAcceptEmail != null && details.data.folder != folder.path,
      onAcceptWithDetails: (details) => onAcceptEmail?.call(details.data),
      builder: (context, candidates, _) => _tile(
        context,
        side: side,
        color: color,
        read: read,
        highlighted: candidates.isNotEmpty,
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required dynamic side,
    required Color color,
    required int read,
    required bool highlighted,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: '${folder.unread} non lu${folder.unread > 1 ? 's' : ''} · '
            '$read lu${read > 1 ? 's' : ''} · '
            '${folder.total} au total',
        waitDuration: const Duration(milliseconds: 600),
        child: Material(
          color: highlighted
              ? AppColors.accentOf(context).withValues(alpha: 0.55)
              : selected
                  ? AppColors.accentOf(context).withValues(alpha: 0.35)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            hoverColor: (side as dynamic).text.withValues(alpha: 0.10)
                as Color,
            onTap: onTap,
            onSecondaryTapDown: onContextMenu == null
                ? null
                : (details) => onContextMenu!(details.globalPosition),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Consumer(builder: (context, ref, _) {
                    final custom = ref
                        .watch(prefsProvider)
                        .value
                        ?.folderColors[folder.path];
                    return Icon(icon,
                        size: 19,
                        color: custom != null ? Color(custom) : color);
                  }),
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
                      style: TextStyle(
                        color: side.muted,
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
          Icon(Icons.cloud_off_rounded,
              color: AppColors.sidebarOf(context).muted, size: 32),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: AppColors.sidebarOf(context).text, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: Text('Réessayer',
                style: TextStyle(
                    color: AppColors.sidebarOf(context).textSelected)),
          ),
        ],
      ),
    );
  }
}
