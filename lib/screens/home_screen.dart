import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/email.dart';
import '../providers/config_provider.dart';
import '../providers/email_provider.dart';
import '../providers/folder_provider.dart';
import '../widgets/email_list_tile.dart';
import '../widgets/email_reader.dart';
import '../widgets/folder_sidebar.dart';
import 'compose_screen.dart';
import 'setup_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  Email? _selected;
  String? _selectedBody;
  bool _selectedBodyIsHtml = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_refreshAll);
  }

  /// Emails and folder counts refresh in parallel — they run on two
  /// separate IMAP connections so neither delays the other.
  Future<void> _refreshAll() async {
    await Future.wait([
      ref.read(emailListProvider.notifier).sync(),
      ref.read(folderListProvider.notifier).refresh(),
    ]);
  }

  Future<void> _openEmail(Email email) async {
    setState(() {
      _selected = email;
      _selectedBody = null;
      _selectedBodyIsHtml = false;
    });

    try {
      // Body first — it's what the user is waiting for; the read-flag
      // push happens afterwards on the same connection.
      final (body, isHtml) =
          await ref.read(emailListProvider.notifier).fetchBody(email);
      if (mounted && _selected?.uid == email.uid) {
        setState(() {
          _selectedBody = body;
          _selectedBodyIsHtml = isHtml;
        });
      }
    } catch (e) {
      if (mounted && _selected?.uid == email.uid) {
        setState(() {
          _selectedBody = 'Erreur de chargement : $e';
          _selectedBodyIsHtml = false;
        });
      }
    }

    if (!email.isRead) {
      await ref.read(emailListProvider.notifier).markRead(email.uid, true);
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        width: 420,
        duration: const Duration(seconds: 3),
      ));
  }

  /// Optimistic delete: the list updates instantly; a SnackBar confirms
  /// or reports a server failure (the email is restored by the provider).
  Future<void> _deleteEmail(Email email) async {
    if (_selected?.uid == email.uid) {
      setState(() => _selected = null);
    }
    try {
      final movedToTrash =
          await ref.read(emailListProvider.notifier).deleteEmail(email.uid);
      _notify(movedToTrash
          ? 'Email déplacé vers la corbeille'
          : 'Email supprimé définitivement');
    } catch (e) {
      _notify('Échec de la suppression — email restauré ($e)');
    }
  }

  void _replyTo(Email email) => _openCompose(
        to: email.fromEmail.isNotEmpty ? email.fromEmail : email.from,
        subject: 'Re: ${email.subject}',
      );

  void _forward(Email email, {String body = ''}) => _openCompose(
        subject: 'Fwd: ${email.subject}',
        body: body,
      );

  /// J/K navigation: opens the next/previous email in the list.
  void _openSibling(int delta) {
    final emails = ref.read(emailListProvider).value;
    if (emails == null || emails.isEmpty) return;
    final selected = _selected;
    var index = selected == null
        ? -1
        : emails.indexWhere((email) => email.uid == selected.uid);
    index = (index + delta).clamp(0, emails.length - 1);
    if (selected?.uid != emails[index].uid) {
      _openEmail(emails[index]);
    }
  }

  /// Reader shortcuts (toolbar hints: R, F, U, ⌫; J/K to navigate).
  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final selected = _selected;
    return {
      const SingleActivator(LogicalKeyboardKey.keyJ): () => _openSibling(1),
      const SingleActivator(LogicalKeyboardKey.keyK): () => _openSibling(-1),
      if (selected != null) ...{
        const SingleActivator(LogicalKeyboardKey.keyR): () =>
            _replyTo(selected),
        const SingleActivator(LogicalKeyboardKey.keyF): () => _forward(
              selected,
              body: _selectedBodyIsHtml ? '' : (_selectedBody ?? ''),
            ),
        const SingleActivator(LogicalKeyboardKey.keyU): () async {
          await ref
              .read(emailListProvider.notifier)
              .markRead(selected.uid, !selected.isRead);
          setState(() =>
              _selected = selected.copyWith(isRead: !selected.isRead));
        },
        const SingleActivator(LogicalKeyboardKey.backspace): () =>
            _deleteEmail(selected),
        const SingleActivator(LogicalKeyboardKey.delete): () =>
            _deleteEmail(selected),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            setState(() => _selected = null),
      },
    };
  }

  Future<void> _openCompose(
      {String to = '', String subject = '', String body = ''}) async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => ComposeScreen(
        initialTo: to,
        initialSubject: subject,
        initialBody: body,
      ),
    );
    if (sent == true && mounted) {
      _notify('Message envoyé');
      // Bump the Envoyés counter in the background.
      ref.read(folderListProvider.notifier).refresh();
    }
  }

  Future<void> _openSettings() async {
    final config = ref.read(accountConfigProvider).value;
    if (config == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SetupScreen(initialConfig: config),
      ),
    );
    if (saved == true && mounted) {
      _notify('Paramètres enregistrés');
      setState(() => _selected = null);
      await _refreshAll();
    }
  }

  Future<void> _addAccount() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const SetupScreen(isAddingAccount: true),
      ),
    );
    if (added == true && mounted) {
      _notify('Compte ajouté');
      setState(() => _selected = null);
      await _refreshAll();
    }
  }

  String _folderLabel(String path) {
    if (path.toLowerCase() == 'inbox') return 'Boîte de réception';
    return path.split('/').last;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    // The opened email belongs to the previous account after a switch.
    ref.listen(currentAccountProvider.select((account) => account?.id),
        (previous, next) {
      if (previous != next && _selected != null) {
        setState(() {
          _selected = null;
          _selectedBody = null;
        });
      }
    });

    final sidebar = FolderSidebar(
      onCompose: () {
        if (!isDesktop) Navigator.of(context).maybePop();
        _openCompose();
      },
      onOpenSettings: () {
        if (!isDesktop) Navigator.of(context).maybePop();
        _openSettings();
      },
      onAddAccount: () {
        if (!isDesktop) Navigator.of(context).maybePop();
        _addAccount();
      },
      onFolderSelected: isDesktop
          ? null
          : () {
              Navigator.of(context).maybePop();
              setState(() => _selected = null);
            },
    );

    if (isDesktop) {
      return Scaffold(
        body: CallbackShortcuts(
          bindings: _shortcuts,
          child: Focus(
            autofocus: true,
            child: Row(
              children: [
                SizedBox(width: 240, child: sidebar),
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      _EmailListHeader(label: _folderLabel(
                          ref.watch(currentFolderProvider))),
                      const Divider(),
                      Expanded(child: _buildEmailList()),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(flex: 3, child: _buildDetail()),
              ],
            ),
          ),
        ),
      );
    }

    // Mobile: drawer + list, reader takes over full screen when selected.
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: _selected != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _selected = null),
              )
            : IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
        title: Text(_selected == null
            ? _folderLabel(ref.watch(currentFolderProvider))
            : ''),
        actions: [
          if (_selected == null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(emailListProvider.notifier).sync(),
            ),
        ],
      ),
      drawer: Drawer(child: sidebar),
      floatingActionButton: _selected == null
          ? FloatingActionButton(
              onPressed: () => _openCompose(),
              child: const Icon(Icons.edit_rounded),
            )
          : null,
      body: _selected == null ? _buildEmailList() : _buildDetail(),
    );
  }

  Widget _buildEmailList() {
    final emailsAsync = ref.watch(emailListProvider);

    return emailsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorPane(
        message: '$error',
        onRetry: () => ref.read(emailListProvider.notifier).sync(),
      ),
      data: (emails) {
        if (emails.isEmpty) {
          return _EmptyPane(
            icon: Icons.inbox_rounded,
            message: 'Aucun email dans ce dossier',
            onRefresh: () => ref.read(emailListProvider.notifier).sync(),
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref.read(emailListProvider.notifier).sync(),
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            itemCount: emails.length,
            itemBuilder: (context, index) {
              final email = emails[index];
              return EmailListTile(
                email: email,
                selected: _selected?.uid == email.uid,
                onTap: () => _openEmail(email),
                onReply: () => _replyTo(email),
                onForward: () => _forward(email),
                onToggleRead: () => ref
                    .read(emailListProvider.notifier)
                    .markRead(email.uid, !email.isRead),
                onDelete: () => _deleteEmail(email),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDetail() {
    final selected = _selected;
    if (selected == null) {
      return const _EmptyPane(
        icon: Icons.drafts_outlined,
        message: 'Sélectionnez un email pour le lire',
      );
    }
    return EmailReader(
      email: selected,
      body: _selectedBody,
      bodyIsHtml: _selectedBodyIsHtml,
      onReply: () => _replyTo(selected),
      onForward: () => _forward(
        selected,
        body: _selectedBodyIsHtml ? '' : (_selectedBody ?? ''),
      ),
      onDelete: () => _deleteEmail(selected),
      onToggleRead: () async {
        await ref
            .read(emailListProvider.notifier)
            .markRead(selected.uid, !selected.isRead);
        setState(
            () => _selected = selected.copyWith(isRead: !selected.isRead));
      },
    );
  }
}

class _EmailListHeader extends ConsumerWidget {
  const _EmailListHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isSyncing = ref.watch(emailListProvider).isLoading ||
        ref.watch(emailSyncingProvider);
    final currentPath = ref.watch(currentFolderProvider);
    final folder = ref
        .watch(folderListProvider)
        .value
        ?.where((f) => f.path == currentPath)
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (folder != null && folder.total > 0)
                  Text(
                    '${folder.total} message${folder.total > 1 ? 's' : ''}'
                    '${folder.unread > 0 ? ' · ${folder.unread} non lu${folder.unread > 1 ? 's' : ''}' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (isSyncing)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: () {
                ref.read(emailListProvider.notifier).sync();
                ref.read(folderListProvider.notifier).refresh();
              },
            ),
        ],
      ),
    );
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({
    required this.icon,
    required this.message,
    this.onRefresh,
  });

  final IconData icon;
  final String message;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: scheme.outlineVariant),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (onRefresh != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Actualiser'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
