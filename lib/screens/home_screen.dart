import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/email.dart';
import '../models/prefs.dart';
import '../providers/config_provider.dart';
import '../providers/email_provider.dart';
import '../providers/folder_provider.dart';
import '../providers/inbox_watcher.dart';
import '../providers/prefs_provider.dart';
import '../providers/undo_provider.dart';
import '../theme.dart';
import '../widgets/email_list_tile.dart';
import '../widgets/email_reader.dart';
import '../widgets/folder_sidebar.dart';
import 'appearance_dialog.dart';
import 'compose_screen.dart';
import 'label_picker_dialog.dart';
import 'setup_screen.dart';

/// Runs [doSend] after the configurable undo window ([delaySeconds],
/// 0 = immediately). The SnackBar disappears the moment the send fires.
void scheduleSend(
  ScaffoldMessengerState messenger,
  Future<void> Function() doSend, {
  int delaySeconds = 10,
  VoidCallback? onSent,
}) {
  Future<void> run() async {
    try {
      await doSend();
      onSent?.call();
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text('Message envoyé'),
          behavior: SnackBarBehavior.floating,
          width: 420,
          duration: Duration(seconds: 2),
        ));
    } catch (e) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('Échec de l\'envoi : $e'),
          behavior: SnackBarBehavior.floating,
          width: 420,
          duration: const Duration(seconds: 6),
        ));
    }
  }

  if (delaySeconds <= 0) {
    run();
    return;
  }

  var cancelled = false;
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text('Envoi dans $delaySeconds s…'),
      behavior: SnackBarBehavior.floating,
      width: 420,
      duration: Duration(seconds: delaySeconds),
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () {
          cancelled = true;
          messenger
            ..clearSnackBars()
            ..showSnackBar(const SnackBar(
              content: Text('Envoi annulé'),
              behavior: SnackBarBehavior.floating,
              width: 420,
              duration: Duration(seconds: 2),
            ));
        },
      ),
    ));
  Timer(Duration(seconds: delaySeconds), () {
    if (cancelled) return;
    messenger.hideCurrentSnackBar();
    run();
  });
}

/// Plain-text quote of the original message for replies.
String quoteBody(Email email, String? body, bool isHtml) {
  if (body == null || body.trim().isEmpty) return '';
  var text = body;
  if (isHtml) {
    text = text
        .replaceAll(RegExp(r'<(br|/p|/div|/tr)[^>]*>', caseSensitive: false),
            '\n')
        .replaceAll(RegExp(r'<(style|script)[\s\S]*?</(style|script)>',
            caseSensitive: false), '')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"');
    text = text
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }
  final quoted =
      text.trim().split('\n').map((line) => '> $line').join('\n');
  return '\n\nLe ${formatEmailDate(email.date)}, ${email.from} a écrit :\n$quoted';
}

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

  // Pane resizing: live value while dragging, persisted on release.
  double? _dragSidebarWidth;
  double? _dragListWidth;

  // Search: instant local filter; Enter runs a server-side search.
  final _searchController = TextEditingController();
  bool _searchOpen = false;
  String _localQuery = '';
  bool _serverResults = false;

  /// UIDs checked for bulk actions.
  final Set<int> _checked = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _hideReader =>
      (ref.read(prefsProvider).value ?? const AppPrefs()).hideReader &&
      MediaQuery.of(context).size.width > 800;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _refreshAll();
      // Start the new-mail watcher (in-app notifications + badge).
      ref.read(inboxWatcherProvider);
    });
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
    if (_hideReader) {
      // Reader pane hidden: the email opens as a full-screen page.
      setState(() => _selected = email);
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _ReaderScreen(email: email)),
      );
      return;
    }
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

  void _replyTo(Email email, {String quote = ''}) => _openCompose(
        to: email.fromEmail.isNotEmpty ? email.fromEmail : email.from,
        subject: 'Re: ${email.subject}',
        body: quote,
      );

  void _forward(Email email, {String body = ''}) => _openCompose(
        subject: 'Fwd: ${email.subject}',
        body: body,
      );

  /// J/K navigation: opens the next/previous email — or only moves the
  /// highlight when the reader pane is hidden (Enter then opens).
  void _openSibling(int delta) {
    final emails = ref.read(emailListProvider).value;
    if (emails == null || emails.isEmpty) return;
    final selected = _selected;
    var index = selected == null
        ? -1
        : emails.indexWhere((email) => email.uid == selected.uid);
    index = (index + delta).clamp(0, emails.length - 1);
    if (selected?.uid == emails[index].uid) return;
    if (_hideReader) {
      setState(() => _selected = emails[index]);
    } else {
      _openEmail(emails[index]);
    }
  }

  /// Letter shortcuts must not fire while the user types in a text field
  /// (the search bar lives in the same focus scope).
  static bool get _isTyping {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  VoidCallback _guarded(VoidCallback action) => () {
        if (!_isTyping) action();
      };

  void _openLabels(Email email) {
    showDialog<void>(
      context: context,
      builder: (_) => LabelPickerDialog(email: email),
    );
  }

  /// Folder picker (mobile "move" action). Moving to the chosen folder is
  /// optimistic and undoable via the provider.
  Future<void> _moveToFolderSheet(Email email) async {
    final folders = ref.read(folderListProvider).value ?? const [];
    final current = ref.read(currentFolderProvider);
    final targets = folders.where((f) => f.path != current).toList();
    if (targets.isEmpty) return;

    final target = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Déplacer vers…',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            for (final folder in targets)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(_folderLabel(folder.path)),
                onTap: () => Navigator.of(context).pop(folder.path),
              ),
          ],
        ),
      ),
    );
    if (target == null) return;
    try {
      await ref.read(emailListProvider.notifier).moveToFolder(
            email.uid,
            target,
            undoLabel: 'Déplacement',
          );
      _notify('Déplacé — ⌘Z / annuler pour revenir');
    } catch (e) {
      _notify('Échec du déplacement : $e');
    }
  }

  Future<void> _undoLast() async {
    final label = await ref.read(undoProvider.notifier).undoLast();
    _notify(label == null ? 'Rien à annuler' : 'Annulé : $label');
  }

  /// Reader shortcuts (toolbar hints: R, F, U, ⌫; J/K to navigate).
  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final selected = _selected;
    return {
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
          _guarded(_undoLast),
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
          _guarded(_undoLast),
      const SingleActivator(LogicalKeyboardKey.keyJ):
          _guarded(() => _openSibling(1)),
      const SingleActivator(LogicalKeyboardKey.keyK):
          _guarded(() => _openSibling(-1)),
      if (selected != null) ...{
        const SingleActivator(LogicalKeyboardKey.keyR): _guarded(() =>
            _replyTo(selected,
                quote:
                    quoteBody(selected, _selectedBody, _selectedBodyIsHtml))),
        const SingleActivator(LogicalKeyboardKey.keyF): _guarded(() =>
            _forward(selected,
                body: _selectedBodyIsHtml ? '' : (_selectedBody ?? ''))),
        const SingleActivator(LogicalKeyboardKey.keyU): _guarded(() async {
          await ref
              .read(emailListProvider.notifier)
              .markRead(selected.uid, !selected.isRead);
          setState(() =>
              _selected = selected.copyWith(isRead: !selected.isRead));
        }),
        const SingleActivator(LogicalKeyboardKey.backspace):
            _guarded(() => _deleteEmail(selected)),
        const SingleActivator(LogicalKeyboardKey.delete):
            _guarded(() => _deleteEmail(selected)),
        const SingleActivator(LogicalKeyboardKey.escape):
            _guarded(() => setState(() => _selected = null)),
        const SingleActivator(LogicalKeyboardKey.keyL):
            _guarded(() => _openLabels(selected)),
        const SingleActivator(LogicalKeyboardKey.enter): _guarded(() {
          if (_hideReader) _openEmail(selected);
        }),
      },
    };
  }

  // --- Search ---------------------------------------------------------------

  void _onSearchChanged(String value) {
    setState(() => _localQuery = value.trim());
  }

  Future<void> _onSearchSubmitted(String value) async {
    final query = value.trim();
    if (query.isEmpty) return;
    setState(() => _serverResults = true);
    await ref.read(emailListProvider.notifier).searchServer(query);
  }

  void _clearSearch() {
    _searchController.clear();
    final hadServerResults = _serverResults;
    setState(() {
      _searchOpen = false;
      _localQuery = '';
      _serverResults = false;
    });
    if (hadServerResults) {
      ref.read(emailListProvider.notifier).sync();
    }
  }

  List<Email> _applyLocalFilter(List<Email> emails) {
    if (_localQuery.isEmpty || _serverResults) return emails;
    final query = _localQuery.toLowerCase();
    return emails
        .where((email) =>
            email.from.toLowerCase().contains(query) ||
            email.fromEmail.toLowerCase().contains(query) ||
            email.subject.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _openCompose(
      {String to = '', String subject = '', String body = ''}) async {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final compose = ComposeScreen(
      initialTo: to,
      initialSubject: subject,
      initialBody: body,
    );
    // Full-screen route on phones, centered dialog on desktop.
    final result = isMobile
        ? await Navigator.of(context).push<Object>(
            MaterialPageRoute(builder: (_) => compose, fullscreenDialog: true),
          )
        : await showDialog<Object>(
            context: context, builder: (_) => compose);
    if (result is Future<void> Function() && mounted) {
      scheduleSend(
        ScaffoldMessenger.of(context),
        result,
        delaySeconds:
            ref.read(prefsProvider).value?.undoSendSeconds ?? 10,
        onSent: () {
          if (mounted) {
            ref.read(folderListProvider.notifier).refresh();
          }
        },
      );
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

  // --- Bulk actions ----------------------------------------------------------

  Future<void> _bulkMarkRead() async {
    final notifier = ref.read(emailListProvider.notifier);
    for (final uid in _checked.toList()) {
      await notifier.markRead(uid, true);
    }
    setState(() => _checked.clear());
  }

  Future<void> _bulkFlag() async {
    final notifier = ref.read(emailListProvider.notifier);
    for (final uid in _checked.toList()) {
      await notifier.toggleFlagged(uid);
    }
    setState(() => _checked.clear());
  }

  Future<void> _bulkDelete() async {
    final uids = _checked.toList();
    setState(() => _checked.clear());
    final notifier = ref.read(emailListProvider.notifier);
    var failures = 0;
    for (final uid in uids) {
      try {
        await notifier.deleteEmail(uid);
      } catch (_) {
        failures++;
      }
    }
    _notify(failures == 0
        ? '${uids.length} email${uids.length > 1 ? 's' : ''} supprimé${uids.length > 1 ? 's' : ''}'
        : 'Suppression partielle : $failures échec${failures > 1 ? 's' : ''}');
  }

  Widget _buildSelectionBar() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      color: scheme.surfaceContainerHigh,
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_checked.length} sélectionné${_checked.length > 1 ? 's' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Marquer lus',
            icon: const Icon(Icons.mark_email_read_outlined, size: 20),
            onPressed: _bulkMarkRead,
          ),
          IconButton(
            tooltip: 'Étoile',
            icon: const Icon(Icons.star_outline_rounded, size: 20),
            onPressed: _bulkFlag,
          ),
          IconButton(
            tooltip: 'Supprimer',
            icon: Icon(Icons.delete_outline_rounded,
                size: 20, color: scheme.error),
            onPressed: _bulkDelete,
          ),
          IconButton(
            tooltip: 'Annuler la sélection',
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _checked.clear()),
          ),
        ],
      ),
    );
  }

  /// Folder title + counts + search toggle, and the search bar when open.
  Widget _buildListHeader() {
    final scheme = Theme.of(context).colorScheme;
    if (_checked.isNotEmpty) return _buildSelectionBar();
    return Column(
      children: [
        _EmailListHeader(
          label: _folderLabel(ref.watch(currentFolderProvider)),
          searchOpen: _searchOpen,
          onToggleSearch: () {
            if (_searchOpen) {
              _clearSearch();
            } else {
              setState(() => _searchOpen = true);
            }
          },
        ),
        if (_searchOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _onSearchChanged,
              onSubmitted: _onSearchSubmitted,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Rechercher — Entrée pour chercher sur le serveur',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: _clearSearch,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        if (_serverResults)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 4),
            child: Row(
              children: [
                Icon(Icons.cloud_done_outlined,
                    size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Résultats de la recherche serveur',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
                TextButton(
                  onPressed: _clearSearch,
                  child: const Text('Effacer', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
      ],
    );
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
    // Checked emails belong to the previous folder.
    ref.listen(currentFolderProvider, (previous, next) {
      if (previous != next && _checked.isNotEmpty) {
        setState(() => _checked.clear());
      }
    });

    final sidebar = FolderSidebar(
      onCompose: () {
        if (!isDesktop) Navigator.of(context).maybePop();
        _openCompose();
      },
      onSync: () {
        if (!isDesktop) Navigator.of(context).maybePop();
        _refreshAll();
        _notify('Synchronisation…');
      },
      onOpenSettings: () {
        if (!isDesktop) Navigator.of(context).maybePop();
        _openSettings();
      },
      onAddAccount: () {
        if (!isDesktop) Navigator.of(context).maybePop();
        _addAccount();
      },
      onOpenAppearance: () {
        if (!isDesktop) Navigator.of(context).maybePop();
        showDialog<void>(
          context: context,
          builder: (_) => const AppearanceDialog(),
        );
      },
      onFolderSelected: isDesktop
          ? null
          : () {
              Navigator.of(context).maybePop();
              setState(() => _selected = null);
            },
    );

    if (isDesktop) {
      final prefs = ref.watch(prefsProvider).value ?? const AppPrefs();
      final sidebarWidth =
          (_dragSidebarWidth ?? prefs.sidebarWidth).clamp(180.0, 340.0);
      final listWidth =
          (_dragListWidth ?? prefs.listWidth).clamp(280.0, 640.0);

      final listColumn = Column(
        children: [
          _buildListHeader(),
          const Divider(),
          Expanded(child: _buildEmailList()),
        ],
      );

      return Scaffold(
        body: CallbackShortcuts(
          bindings: _searchOpen
              ? {
                  const SingleActivator(LogicalKeyboardKey.escape):
                      _clearSearch,
                }
              : _shortcuts,
          child: Focus(
            autofocus: true,
            child: Row(
              children: [
                SizedBox(width: sidebarWidth, child: sidebar),
                _PaneHandle(
                  onDelta: (dx) => setState(() => _dragSidebarWidth =
                      ((_dragSidebarWidth ?? prefs.sidebarWidth) + dx)
                          .clamp(180.0, 340.0)),
                  onEnd: () {
                    final width = _dragSidebarWidth;
                    if (width != null) {
                      ref
                          .read(prefsProvider.notifier)
                          .apply(sidebarWidth: width);
                    }
                  },
                ),
                if (prefs.hideReader)
                  Expanded(child: listColumn)
                else ...[
                  SizedBox(width: listWidth, child: listColumn),
                  _PaneHandle(
                    onDelta: (dx) => setState(() => _dragListWidth =
                        ((_dragListWidth ?? prefs.listWidth) + dx)
                            .clamp(280.0, 640.0)),
                    onEnd: () {
                      final width = _dragListWidth;
                      if (width != null) {
                        ref
                            .read(prefsProvider.notifier)
                            .apply(listWidth: width);
                      }
                    },
                  ),
                  Expanded(child: _buildDetail()),
                ],
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
      data: (allEmails) {
        final emails = _applyLocalFilter(allEmails);
        if (emails.isEmpty) {
          return _EmptyPane(
            icon: _localQuery.isNotEmpty || _serverResults
                ? Icons.search_off_rounded
                : Icons.inbox_rounded,
            message: _localQuery.isNotEmpty || _serverResults
                ? 'Aucun résultat'
                : 'Aucun email dans ce dossier',
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
                selectionMode: _checked.isNotEmpty,
                checked: _checked.contains(email.uid),
                onCheckChanged: (checked) => setState(() {
                  if (checked) {
                    _checked.add(email.uid);
                  } else {
                    _checked.remove(email.uid);
                  }
                }),
                onTap: () => _openEmail(email),
                onReply: () => _replyTo(email),
                onForward: () => _forward(email),
                onToggleRead: () => ref
                    .read(emailListProvider.notifier)
                    .markRead(email.uid, !email.isRead),
                onDelete: () => _deleteEmail(email),
                onToggleFlag: () =>
                    ref.read(emailListProvider.notifier).toggleFlagged(email.uid),
                onLabel: () => _openLabels(email),
                onMove: () => _moveToFolderSheet(email),
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
      onReply: () => _replyTo(selected,
          quote: quoteBody(selected, _selectedBody, _selectedBodyIsHtml)),
      onForward: () => _forward(
        selected,
        body: _selectedBodyIsHtml ? '' : (_selectedBody ?? ''),
      ),
      onDelete: () => _deleteEmail(selected),
      onLabel: () => _openLabels(selected),
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
  const _EmailListHeader({
    required this.label,
    this.searchOpen = false,
    this.onToggleSearch,
  });

  final String label;
  final bool searchOpen;
  final VoidCallback? onToggleSearch;

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
          if (onToggleSearch != null)
            IconButton(
              tooltip: searchOpen ? 'Fermer la recherche' : 'Rechercher',
              icon: Icon(
                searchOpen ? Icons.search_off_rounded : Icons.search_rounded,
                size: 20,
              ),
              onPressed: onToggleSearch,
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

/// Draggable vertical divider between two panes.
class _PaneHandle extends StatelessWidget {
  const _PaneHandle({required this.onDelta, required this.onEnd});

  final ValueChanged<double> onDelta;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDelta(details.delta.dx),
        onHorizontalDragEnd: (_) => onEnd(),
        child: SizedBox(
          width: 7,
          child: Center(
            child: Container(
              width: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen reader used when the reader pane is hidden.
class _ReaderScreen extends ConsumerStatefulWidget {
  const _ReaderScreen({required this.email});

  final Email email;

  @override
  ConsumerState<_ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<_ReaderScreen> {
  late Email _email = widget.email;
  String? _body;
  bool _bodyIsHtml = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final (body, isHtml) =
          await ref.read(emailListProvider.notifier).fetchBody(_email);
      if (mounted) {
        setState(() {
          _body = body;
          _bodyIsHtml = isHtml;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _body = 'Erreur de chargement : $e');
    }
    if (!_email.isRead) {
      await ref.read(emailListProvider.notifier).markRead(_email.uid, true);
    }
  }

  Future<void> _compose(
      {String to = '', String subject = '', String body = ''}) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<Object>(
      context: context,
      builder: (_) => ComposeScreen(
        initialTo: to,
        initialSubject: subject,
        initialBody: body,
      ),
    );
    if (result is Future<void> Function()) {
      scheduleSend(messenger, result,
          delaySeconds:
              ref.read(prefsProvider).value?.undoSendSeconds ?? 10);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(_email.subject,
            style: const TextStyle(fontSize: 15),
            overflow: TextOverflow.ellipsis),
      ),
      body: EmailReader(
        email: _email,
        body: _body,
        bodyIsHtml: _bodyIsHtml,
        onReply: () => _compose(
          to: _email.fromEmail.isNotEmpty ? _email.fromEmail : _email.from,
          subject: 'Re: ${_email.subject}',
          body: quoteBody(_email, _body, _bodyIsHtml),
        ),
        onForward: () => _compose(
          subject: 'Fwd: ${_email.subject}',
          body: _bodyIsHtml ? '' : (_body ?? ''),
        ),
        onDelete: () async {
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          try {
            await ref
                .read(emailListProvider.notifier)
                .deleteEmail(_email.uid);
            navigator.pop();
          } catch (e) {
            messenger.showSnackBar(
              SnackBar(content: Text('Échec de la suppression : $e')),
            );
          }
        },
        onLabel: () => showDialog<void>(
          context: context,
          builder: (_) => LabelPickerDialog(email: _email),
        ),
        onToggleRead: () async {
          await ref
              .read(emailListProvider.notifier)
              .markRead(_email.uid, !_email.isRead);
          setState(() => _email = _email.copyWith(isRead: !_email.isRead));
        },
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
