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

  static const _connectTimeout = Duration(seconds: 15);

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
    return fresh;
  }

  /// Drops the connection so the next [ensureConnected] starts clean.
  /// Used after errors where the session state is unknown.
  void reset() {
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

    final mailboxes = await _timed('list', () => client.listMailboxes());
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
  /// Fetches BODYSTRUCTURE first, then only the text/plain (or text/html)
  /// part — never the attachments. `BODY.PEEK[]` would download the whole
  /// raw message, which makes opening any email with attachments crawl.
  Future<MimeMessage> fetchMessageText(String folderPath, int uid) async {
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
    final textPart = body?.findFirst(MediaSubtype.textHtml) ??
        body?.findFirst(MediaSubtype.textPlain);
    final fetchId = textPart?.fetchId;

    if (body == null || fetchId == null) {
      // No parseable structure — fall back to the full raw message.
      final full = await _timed('fetch full body (fallback)',
          () => client.uidFetchMessages(sequence, 'BODY.PEEK[]'));
      if (full.messages.isEmpty) {
        throw StateError('Message introuvable (UID $uid)');
      }
      return full.messages.first;
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
    return message;
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

  /// Permanently deletes a message (used inside the trash folder).
  Future<void> deleteMessage(String folderPath, int uid) async {
    final client = _requireClient;
    await _select(folderPath);
    final sequence = MessageSequence.fromId(uid, isUid: true);
    await client.uidMarkDeleted(sequence);
    await client.expunge();
  }
}
