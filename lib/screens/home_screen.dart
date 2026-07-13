import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(folderListProvider.notifier).refresh();
      ref.read(emailListProvider.notifier).sync();
    });
  }

  Future<void> _openEmail(Email email) async {
    setState(() {
      _selected = email;
      _selectedBody = null;
    });
    if (!email.isRead) {
      await ref.read(emailListProvider.notifier).markRead(email.uid, true);
    }

    final config = ref.read(accountConfigProvider).value;
    final storage = ref.read(storageServiceProvider);
    final password = await storage.readImapPassword();
    if (config == null || password == null) return;

    final imap = ref.read(imapServiceProvider);
    try {
      await imap.connect(config.imap, password);
      final message = await imap.fetchFullMessage(email.folder, email.uid);
      if (mounted && _selected?.uid == email.uid) {
        setState(() {
          _selectedBody = message.decodeTextPlainPart() ??
              message.decodeTextHtmlPart() ??
              '(corps vide)';
        });
      }
    } catch (e) {
      if (mounted && _selected?.uid == email.uid) {
        setState(() => _selectedBody = 'Erreur de chargement : $e');
      }
    } finally {
      await imap.disconnect();
    }
  }

  void _openCompose({String to = '', String subject = '', String body = ''}) {
    showDialog<bool>(
      context: context,
      builder: (_) => ComposeScreen(
        initialTo: to,
        initialSubject: subject,
        initialBody: body,
      ),
    );
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
      ref.read(folderListProvider.notifier).refresh();
      ref.read(emailListProvider.notifier).sync();
    }
  }

  String _folderLabel(String path) {
    if (path.toLowerCase() == 'inbox') return 'Boîte de réception';
    return path.split('/').last;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    final sidebar = FolderSidebar(
      onCompose: () {
        if (!isDesktop) Navigator.of(context).maybePop();
        _openCompose();
      },
      onOpenSettings: () {
        if (!isDesktop) Navigator.of(context).maybePop();
        _openSettings();
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
        body: Row(
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
          child: ListView.separated(
            itemCount: emails.length,
            separatorBuilder: (_, _) => const Divider(indent: 64),
            itemBuilder: (context, index) {
              final email = emails[index];
              return EmailListTile(
                email: email,
                selected: _selected?.uid == email.uid,
                onTap: () => _openEmail(email),
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
      onReply: () => _openCompose(
        to: selected.from,
        subject: 'Re: ${selected.subject}',
      ),
      onForward: () => _openCompose(
        subject: 'Fwd: ${selected.subject}',
        body: _selectedBody ?? '',
      ),
      onDelete: () async {
        await ref.read(emailListProvider.notifier).deleteEmail(selected.uid);
        setState(() => _selected = null);
      },
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
    final isSyncing = ref.watch(emailListProvider).isLoading;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
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
              onPressed: () => ref.read(emailListProvider.notifier).sync(),
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
