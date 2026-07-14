import 'package:enough_mail/enough_mail.dart';

import '../models/config.dart';
import '../models/email.dart';
import '../models/folder.dart';

/// Thin wrapper around `enough_mail`'s low-level [ImapClient].
///
/// One [ImapService] instance owns one connection: call [connect] before
/// any other method, and [disconnect] when done with it.
class ImapService {
  ImapClient? _client;

  static const _connectTimeout = Duration(seconds: 15);

  Future<void> connect(ImapConfig config, String password) async {
    final client = ImapClient(isLogEnabled: false);
    await client
        .connectToServer(config.host, config.port, isSecure: true)
        .timeout(_connectTimeout);
    await client.login(config.username, password).timeout(_connectTimeout);
    _client = client;
  }

  Future<void> disconnect() async {
    await _client?.logout();
    _client = null;
  }

  ImapClient get _requireClient {
    final client = _client;
    if (client == null) {
      throw StateError('ImapService.connect() must be called first');
    }
    return client;
  }

  /// Lists selectable folders with their message counts
  /// (one IMAP STATUS per folder).
  Future<List<Folder>> listFolders() async {
    final client = _requireClient;
    final mailboxes = await client.listMailboxes();
    final folders = <Folder>[];
    for (final box in mailboxes) {
      if (box.isNotSelectable) continue;
      var total = 0;
      var unread = 0;
      try {
        final status = await client.statusMailbox(
          box,
          [StatusFlags.messages, StatusFlags.unseen],
        );
        total = status.messagesExists;
        unread = status.messagesUnseen;
      } catch (_) {
        // STATUS is optional per folder; counts stay at 0 if it fails.
      }
      folders.add(Folder(
        name: box.name,
        path: box.path,
        total: total,
        unread: unread,
      ));
    }
    return folders;
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
    final box = await client.selectMailboxByPath(folderPath);
    if (box.messagesExists == 0) return [];

    final result = await client.fetchRecentMessages(
      messageCount: count,
      criteria: '(UID FLAGS ENVELOPE)',
    );
    return result.messages.map((message) {
      final envelope = message.envelope;
      final fromAddresses = envelope?.from ?? message.from;
      final from = (fromAddresses != null && fromAddresses.isNotEmpty)
          ? (fromAddresses.first.personalName?.isNotEmpty ?? false
              ? fromAddresses.first.personalName!
              : fromAddresses.first.email)
          : '';
      return Email(
        uid: message.uid ?? message.sequenceId ?? 0,
        folder: folderPath,
        from: from,
        subject: envelope?.subject ?? message.decodeSubject() ?? '(sans sujet)',
        date: envelope?.date ?? message.decodeDate() ?? DateTime.now(),
        preview: '',
        isRead: message.isSeen,
      );
    }).toList();
  }

  /// Fetches the full body of a single message by UID for the reader panel.
  Future<MimeMessage> fetchFullMessage(String folderPath, int uid) async {
    final client = _requireClient;
    await client.selectMailboxByPath(folderPath);
    final sequence = MessageSequence.fromId(uid, isUid: true);
    final result = await client.uidFetchMessages(sequence, 'BODY.PEEK[]');
    if (result.messages.isEmpty) {
      throw StateError('Message introuvable (UID $uid)');
    }
    return result.messages.first;
  }

  Future<void> markSeen(String folderPath, int uid, {bool isSeen = true}) async {
    final client = _requireClient;
    await client.selectMailboxByPath(folderPath);
    final sequence = MessageSequence.fromId(uid, isUid: true);
    if (isSeen) {
      await client.uidMarkSeen(sequence);
    } else {
      await client.uidMarkUnseen(sequence);
    }
  }

  Future<void> deleteMessage(String folderPath, int uid) async {
    final client = _requireClient;
    await client.selectMailboxByPath(folderPath);
    final sequence = MessageSequence.fromId(uid, isUid: true);
    await client.uidMarkDeleted(sequence);
    await client.expunge();
  }
}
