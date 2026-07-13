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

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
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
    await imap.connect(config.imap, password);
    try {
      final message = await imap.fetchFullMessage(email.folder, email.uid);
      if (mounted) {
        setState(() {
          _selectedBody = message.decodeTextPlainPart() ??
              message.decodeTextHtmlPart() ??
              '(corps vide)';
        });
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    final emailsAsync = ref.watch(emailListProvider);

    final emailList = emailsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Erreur: $error')),
      data: (emails) => RefreshIndicator(
        onRefresh: () => ref.read(emailListProvider.notifier).sync(),
        child: ListView.builder(
          itemCount: emails.length,
          itemBuilder: (context, index) {
            final email = emails[index];
            return EmailListTile(
              email: email,
              selected: _selected?.uid == email.uid,
              onTap: () => _openEmail(email),
            );
          },
        ),
      ),
    );

    final detail = _selected == null
        ? const Center(child: Text('Sélectionnez un email'))
        : EmailReader(
            email: _selected!,
            body: _selectedBody,
            onReply: () => _openCompose(
              to: _selected!.from,
              subject: 'Re: ${_selected!.subject}',
            ),
            onForward: () => _openCompose(
              subject: 'Fwd: ${_selected!.subject}',
              body: _selectedBody ?? '',
            ),
            onDelete: () async {
              await ref.read(emailListProvider.notifier).deleteEmail(_selected!.uid);
              setState(() => _selected = null);
            },
            onToggleRead: () async {
              final email = _selected!;
              await ref
                  .read(emailListProvider.notifier)
                  .markRead(email.uid, !email.isRead);
              setState(() => _selected = email.copyWith(isRead: !email.isRead));
            },
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenMailbox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Compose',
            onPressed: () => _openCompose(),
          ),
        ],
      ),
      drawer: isDesktop ? null : const Drawer(child: FolderSidebar()),
      body: isDesktop
          ? Row(
              children: [
                const SizedBox(width: 240, child: FolderSidebar()),
                const VerticalDivider(width: 1),
                Expanded(flex: 2, child: emailList),
                const VerticalDivider(width: 1),
                Expanded(flex: 3, child: detail),
              ],
            )
          : (_selected == null
              ? emailList
              : Column(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() => _selected = null),
                    ),
                    Expanded(child: detail),
                  ],
                )),
    );
  }
}
