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

  Future<void> connect(ImapConfig config, String password) async {
    final client = ImapClient(isLogEnabled: false);
    await client.connectToServer(config.host, config.port, isSecure: true);
    await client.login(config.username, password);
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

  Future<List<Folder>> listFolders() async {
    final mailboxes = await _requireClient.listMailboxes();
    return mailboxes
        .map((box) => Folder(name: box.name, path: box.path))
        .toList();
  }

  /// Fetches the [count] most recent messages of [folderPath] as metadata
  /// only (no body), suitable for the email list / local cache.
  Future<List<Email>> fetchRecentMessages(
    String folderPath, {
    int count = 50,
  }) async {
    final client = _requireClient;
    await client.selectMailboxByPath(folderPath);
    final result = await client.fetchRecentMessages(
      messageCount: count,
      criteria: 'BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)]',
    );
    return result.messages.map((message) {
      final body = message.decodeTextPlainPart() ?? '';
      return Email(
        uid: message.uid ?? message.sequenceId ?? 0,
        folder: folderPath,
        from: message.from?.map((a) => a.email).join(', ') ?? '',
        subject: message.decodeSubject() ?? '(sans sujet)',
        date: message.decodeDate() ?? DateTime.now(),
        preview: body.length > 200 ? body.substring(0, 200) : body,
        isRead: message.isSeen,
      );
    }).toList();
  }

  /// Fetches the full body of a single message by UID for the reader panel.
  Future<MimeMessage> fetchFullMessage(String folderPath, int uid) async {
    final client = _requireClient;
    await client.selectMailboxByPath(folderPath);
    final sequence = MessageSequence.fromId(uid, isUid: true);
    final result = await client.fetchMessages(sequence, 'BODY.PEEK[]');
    return result.messages.first;
  }

  Future<void> markSeen(String folderPath, int uid, {bool isSeen = true}) async {
    final client = _requireClient;
    await client.selectMailboxByPath(folderPath);
    final sequence = MessageSequence.fromId(uid, isUid: true);
    if (isSeen) {
      await client.markSeen(sequence);
    } else {
      await client.markUnseen(sequence);
    }
  }

  Future<void> deleteMessage(String folderPath, int uid) async {
    final client = _requireClient;
    await client.selectMailboxByPath(folderPath);
    final sequence = MessageSequence.fromId(uid, isUid: true);
    await client.markDeleted(sequence);
    await client.expunge();
  }
}
