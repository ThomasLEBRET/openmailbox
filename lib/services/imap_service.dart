import 'dart:async';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/foundation.dart';

import '../models/config.dart';
import '../models/email.dart';
import '../models/folder.dart';

/// Thin wrapper around `enough_mail`'s low-level [ImapClient].
///
/// The connection is persistent: [ensureConnected] reuses the existing
/// TLS session instead of paying connect+login on every operation.
/// Call [reset] after a network error so the next call reconnects, and
/// [disconnect] when the account changes.
class ImapService {
  ImapClient? _client;
  ImapConfig? _connectedConfig;
  String? _connectedPassword;
  String? _selectedPath;
  Mailbox? _selectedBox;
  Future<ImapClient>? _connecting;
  Future<void>? _lock;
  Timer? _keepAlive;

  static const _connectTimeout = Duration(seconds: 15);
  static const _keepAliveInterval = Duration(minutes: 2);

  /// Serializes whole operations on this connection. Without this, a
  /// [reset] triggered by one flow while another flow's command is in
  /// flight leaves that command's future pending forever (enough_mail
  /// stashes queued commands on disconnect instead of failing them) —
  /// which showed up as a spinner that never resolved.
  Future<T> runExclusive<T>(Future<T> Function() fn) {
    final previous = _lock;
    final completer = Completer<void>();
    _lock = completer.future;
    return () async {
      if (previous != null) {
        await previous;
      }
      try {
        return await fn();
      } finally {
        completer.complete();
      }
    }();
  }

  /// Keeps the session warm: Mailo drops idle connections, and paying
  /// connect+login (measured up to 3.5s) on the next user action made
  /// refreshes feel slow "for nothing".
  void _startKeepAlive() {
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(_keepAliveInterval, (_) {
      runExclusive(() async {
        final client = _client;
        if (client == null || !client.isConnected) return;
        try {
          await client.noop().timeout(const Duration(seconds: 10));
        } catch (_) {
          reset(); // Dead session: next operation reconnects cleanly.
        }
      });
    });
  }

  /// Times an operation and logs its duration — diagnosis aid for slow
  /// servers. Never logs credentials or message content.
  Future<T> _timed<T>(String label, Future<T> Function() op) async {
    final watch = Stopwatch()..start();
    try {
      return await op();
    } finally {
      debugPrint('[IMAP] $label: ${watch.elapsedMilliseconds}ms');
    }
  }

  Future<ImapClient> ensureConnected(
      ImapConfig config, String password) async {
    final client = _client;
    if (client != null &&
        client.isConnected &&
        client.isLoggedIn &&
        _connectedConfig == config &&
        _connectedPassword == password) {
      return client;
    }
    // Concurrent callers (e.g. folder refresh + email sync at startup)
    // share one connection attempt instead of opening two sockets.
    final pending = _connecting;
    if (pending != null) return pending;

    final attempt = _connect(config, password);
    _connecting = attempt;
    try {
      return await attempt;
    } finally {
      _connecting = null;
    }
  }

  Future<ImapClient> _connect(ImapConfig config, String password) async {
    await disconnect();

    final fresh = ImapClient(isLogEnabled: false);
    await _timed(
        'connect+login',
        () async {
          await fresh
              .connectToServer(config.host, config.port, isSecure: true)
              .timeout(_connectTimeout);
          await fresh.login(config.username, password).timeout(_connectTimeout);
        });
    _client = fresh;
    _connectedConfig = config;
    _connectedPassword = password;
    _selectedPath = null;
    _selectedBox = null;
    _startKeepAlive();
    return fresh;
  }

  /// Drops the connection so the next [ensureConnected] starts clean.
  /// Used after errors where the session state is unknown.
  void reset() {
    _keepAlive?.cancel();
    _keepAlive = null;
    final client = _client;
    _client = null;
    _connectedConfig = null;
    _connectedPassword = null;
    _selectedPath = null;
    _selectedBox = null;
    // Fire-and-forget: the socket may already be dead.
    client?.disconnect().catchError((_) {});
  }

  Future<void> disconnect() async {
    _keepAlive?.cancel();
    _keepAlive = null;
    final client = _client;
    _client = null;
    _connectedConfig = null;
    _connectedPassword = null;
    _selectedPath = null;
    _selectedBox = null;
    if (client != null) {
      try {
        await client.logout();
      } catch (_) {
        // Socket already gone — nothing to clean up.
      }
    }
  }

  ImapClient get _requireClient {
    final client = _client;
    if (client == null) {
      throw StateError('ImapService.ensureConnected() must be called first');
    }
    return client;
  }

  /// Selects [path] unless it is already the active mailbox.
  /// [forceRefresh] re-selects to get fresh message counts.
  Future<Mailbox> _select(String path, {bool forceRefresh = false}) async {
    final client = _requireClient;
    final cached = _selectedBox;
    if (!forceRefresh && _selectedPath == path && cached != null) {
      return cached;
    }
    final box =
        await _timed('select $path', () => client.selectMailboxByPath(path));
    _selectedPath = path;
    _selectedBox = box;
    return box;
  }

  /// Lists selectable folders with their message counts.
  ///
  /// Uses LIST-STATUS (RFC 5819) when the server supports it — one round
  /// trip for everything. The per-folder STATUS fallback is expensive on
  /// slow servers (Mailo: ~330ms per folder).
  Future<List<Folder>> listFolders() async {
    final client = _requireClient;

    if (client.serverInfo.supports('LIST-STATUS')) {
      final mailboxes = await _timed(
        'list-status',
        () => client.listMailboxes(
          // Recursive: Gmail nests everything under "[Gmail]/" — a
          // top-level listing misses Trash, Sent, Drafts entirely.
          recursive: true,
          returnOptions: [
            ReturnOption.status(['MESSAGES', 'UNSEEN']),
          ],
        ),
      );
      return [
        for (final box in mailboxes.where((b) => !b.isNotSelectable))
          Folder(
            name: box.name,
            path: box.path,
            total: box.messagesExists,
            unread: box.messagesUnseen,
          ),
      ];
    }

    final mailboxes =
        await _timed('list', () => client.listMailboxes(recursive: true));
    final selectable =
        mailboxes.where((box) => !box.isNotSelectable).toList();

    final statuses = await _timed(
        'status x${selectable.length}',
        () => Future.wait(selectable.map((box) async {
              try {
                final status = await client.statusMailbox(
                  box,
                  [StatusFlags.messages, StatusFlags.unseen],
                );
                return (status.messagesExists, status.messagesUnseen);
              } catch (_) {
                return (0, 0); // STATUS is optional per folder.
              }
            })));

    return [
      for (var i = 0; i < selectable.length; i++)
        Folder(
          name: selectable[i].name,
          path: selectable[i].path,
          total: statuses[i].$1,
          unread: statuses[i].$2,
        ),
    ];
  }

  /// Fetches the [count] most recent messages of [folderPath] as metadata
  /// only — UID, flags and envelope; no body. `(UID FLAGS ENVELOPE)` is
  /// plain RFC 3501, unlike header-field peeks that some servers
  /// (e.g. Mailo) reject with "BAD FETCH bad parameter".
  Future<List<Email>> fetchRecentMessages(
    String folderPath, {
    int count = 50,
  }) async {
    final client = _requireClient;
    final box = await _select(folderPath, forceRefresh: true);
    if (box.messagesExists == 0) return [];

    final result = await _timed(
      'fetch envelopes',
      () => client.fetchRecentMessages(
        messageCount: count,
        criteria: '(UID FLAGS ENVELOPE)',
      ),
    );
    return result.messages.map((message) {
      final envelope = message.envelope;
      final fromAddresses = envelope?.from ?? message.from;
      final sender = (fromAddresses != null && fromAddresses.isNotEmpty)
          ? fromAddresses.first
          : null;
      final from = sender == null
          ? ''
          : (sender.personalName?.isNotEmpty ?? false)
              ? sender.personalName!
              : sender.email;
      return Email(
        uid: message.uid ?? message.sequenceId ?? 0,
        folder: folderPath,
        from: from,
        fromEmail: sender?.email ?? '',
        subject: envelope?.subject ?? message.decodeSubject() ?? '(sans sujet)',
        date: envelope?.date ?? message.decodeDate() ?? DateTime.now(),
        preview: '',
        isRead: message.isSeen,
      );
    }).toList();
  }

  /// Fetches the readable text of a single message for the reader panel.
  ///
  /// Fetches BODYSTRUCTURE first, then only the text/html (or text/plain)
  /// part — never the attachments. `BODY.PEEK[]` would download the whole
  /// raw message, which makes opening any email with attachments crawl.
  ///
  /// The second field says which part was fetched: true = text/html,
  /// false = text/plain, null = full-message fallback (caller decides).
  Future<(MimeMessage, bool?)> fetchMessageText(
      String folderPath, int uid) async {
    final client = _requireClient;
    await _select(folderPath);
    final sequence = MessageSequence.fromId(uid, isUid: true);

    final structureResult = await _timed('fetch bodystructure',
        () => client.uidFetchMessages(sequence, '(BODYSTRUCTURE)'));
    if (structureResult.messages.isEmpty) {
      throw StateError('Message introuvable (UID $uid)');
    }
    final message = structureResult.messages.first;
    final body = message.body;
    // HTML first: it's the authored version of most emails and the
    // reader renders it; plain text is the fallback.
    final htmlPart = body?.findFirst(MediaSubtype.textHtml);
    final textPart = htmlPart ?? body?.findFirst(MediaSubtype.textPlain);
    final fetchId = textPart?.fetchId;

    if (body == null || fetchId == null) {
      // No parseable structure — fall back to the full raw message.
      final full = await _timed('fetch full body (fallback)',
          () => client.uidFetchMessages(sequence, 'BODY.PEEK[]'));
      if (full.messages.isEmpty) {
        throw StateError('Message introuvable (UID $uid)');
      }
      return (full.messages.first, null);
    }

    final partResult = await _timed('fetch part $fetchId',
        () => client.uidFetchMessages(sequence, '(BODY.PEEK[$fetchId])'));
    final fetchedPart = partResult.messages.isNotEmpty
        ? partResult.messages.first.getPart(fetchId)
        : null;
    if (fetchedPart == null) {
      throw StateError('Partie du message introuvable ($fetchId)');
    }
    message.setPart(fetchId, fetchedPart);
    return (message, htmlPart != null);
  }

  Future<void> markSeen(String folderPath, int uid, {bool isSeen = true}) async {
    final client = _requireClient;
    await _select(folderPath);
    final sequence = MessageSequence.fromId(uid, isUid: true);
    if (isSeen) {
      await client.uidMarkSeen(sequence);
    } else {
      await client.uidMarkUnseen(sequence);
    }
  }

  /// Moves a message to [trashPath] (MOVE, with COPY+DELETE fallback for
  /// servers without the MOVE extension).
  Future<void> moveToTrash(
      String folderPath, int uid, String trashPath) async {
    final client = _requireClient;
    await _select(folderPath);
    final sequence = MessageSequence.fromId(uid, isUid: true);
    try {
      await client.uidMove(sequence, targetMailboxPath: trashPath);
    } on ImapException {
      await client.uidCopy(sequence, targetMailboxPath: trashPath);
      await client.uidMarkDeleted(sequence);
      await client.expunge();
    }
  }

  static const _prefsFolder = 'OpenMailbox_Prefs';

  /// Reads the last synced preferences JSON from the dedicated folder,
  /// or null when none exists yet.
  Future<String?> fetchPrefsJson() async {
    final client = _requireClient;
    final Mailbox box;
    try {
      box = await client.selectMailboxByPath(_prefsFolder);
    } catch (_) {
      return null; // Folder doesn't exist yet — nothing synced.
    }
    _selectedPath = _prefsFolder;
    _selectedBox = box;
    if (box.messagesExists == 0) return null;
    final result = await client.fetchRecentMessages(
      messageCount: 1,
      criteria: 'BODY.PEEK[]',
    );
    if (result.messages.isEmpty) return null;
    return result.messages.last.decodeTextPlainPart();
  }

  /// Stores the preferences JSON as the sole message of the dedicated
  /// folder (creates it on first use, purges previous versions).
  Future<void> pushPrefsJson(String json) async {
    final client = _requireClient;
    try {
      await client.createMailbox(_prefsFolder);
    } catch (_) {
      // Already exists.
    }
    final message = MessageBuilder.buildSimpleTextMessage(
      const MailAddress('OpenMailbox', 'prefs@openmailbox.local'),
      [const MailAddress('OpenMailbox', 'prefs@openmailbox.local')],
      json,
      subject: 'OpenMailbox preferences',
    );
    await client.appendMessage(message, targetMailboxPath: _prefsFolder);
    // Keep only the newest message.
    final box = await client.selectMailboxByPath(_prefsFolder);
    _selectedPath = _prefsFolder;
    _selectedBox = box;
    if (box.messagesExists > 1) {
      final sequence =
          MessageSequence.fromRange(1, box.messagesExists - 1);
      await client.store(sequence, [r'\Deleted']);
      await client.expunge();
    }
  }

  /// Permanently deletes a message (used inside the trash folder).
  Future<void> deleteMessage(String folderPath, int uid) async {
    final client = _requireClient;
    await _select(folderPath);
    final sequence = MessageSequence.fromId(uid, isUid: true);
    await client.uidMarkDeleted(sequence);
    await client.expunge();
  }
}
