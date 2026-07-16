@Tags(['integration'])
library;

import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmailbox/models/config.dart';
import 'package:openmailbox/services/imap_service.dart';

/// End-to-end tests against a real IMAP server (GreenMail) — catches the
/// server-facing behaviour that fakes can't (MOVE/COPY+EXPUNGE, LIST-STATUS,
/// SEARCH BEFORE, real UID handling).
///
/// Start GreenMail first:
///   java -Dgreenmail.setup.test.all -Dgreenmail.users=test:pw@localhost \
///        -Dgreenmail.auth.disabled -jar tools/greenmail-standalone.jar
/// then: flutter test test/imap_integration_test.dart
///
/// Skips itself cleanly if GreenMail isn't reachable on localhost:3143.
const _host = 'localhost';
const _imapPort = 3143;
const _smtpPort = 3025;
const _imapUser = 'test'; // GreenMail login name (NOT the email address)
const _smtpTo = 'test@localhost'; // delivery address
const _pw = 'pw';

Future<bool> _reachable() async {
  try {
    final s = await Socket.connect(_host, _imapPort,
        timeout: const Duration(milliseconds: 500));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// Unique subject base per test run, so assertions aren't polluted by
/// messages left in GreenMail's in-memory store by earlier runs.
String _uniq(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}';

Future<void> _send(int n, {String subject = 'Subject'}) async {
  final client = SmtpClient('openmailbox.test', isLogEnabled: false);
  await client.connectToServer(_host, _smtpPort, isSecure: false);
  await client.ehlo();
  for (var i = 0; i < n; i++) {
    final message = MessageBuilder.buildSimpleTextMessage(
      const MailAddress('Sender', 'sender@example.com'),
      [const MailAddress('Test', _smtpTo)],
      'Body $i',
      subject: '$subject $i',
    );
    await client.sendMessage(message);
  }
  await client.disconnect();
}

void main() {
  const config = ImapConfig(host: _host, port: _imapPort, username: _imapUser);
  late bool up;

  setUpAll(() async {
    up = await _reachable();
  });

  Future<ImapService> connect() async {
    final imap = ImapService(secure: false);
    await imap.ensureConnected(config, _pw);
    return imap;
  }

  test('INBOX reflects delivered mail; moveMessages relocates them', () async {
    if (!up) {
      markTestSkipped('GreenMail not running on localhost:3143');
      return;
    }
    final subj = _uniq('MoveTest');
    await _send(3, subject: subj);
    final imap = await connect();
    try {
      // GreenMail creates the mailbox but enough_mail's post-create LIST
      // verification trips on its namespace — the folder still exists, so
      // tolerate it (real servers like Mailo don't hit this).
      try {
        await imap.createFolder('Archive');
      } catch (_) {}

      final recent = await imap.runExclusive(
          () => imap.fetchRecentMessages('INBOX', count: 50));
      final subjects = recent.map((e) => e.subject).toList();
      expect(subjects.where((s) => s.startsWith(subj)), hasLength(3));

      final uids = recent
          .where((e) => e.subject.startsWith(subj))
          .map((e) => e.uid)
          .toList();
      await imap.runExclusive(
          () => imap.moveMessages('INBOX', uids, 'Archive'));

      final afterInbox = await imap.runExclusive(
          () => imap.fetchRecentMessages('INBOX', count: 50));
      expect(afterInbox.where((e) => e.subject.startsWith(subj)), isEmpty);

      final archive = await imap.runExclusive(
          () => imap.fetchRecentMessages('Archive', count: 50));
      expect(archive.where((e) => e.subject.startsWith(subj)), hasLength(3));
    } finally {
      await imap.disconnect();
    }
  });

  test('deleteMessages + emptyFolder permanently remove mail', () async {
    if (!up) {
      markTestSkipped('GreenMail not running on localhost:3143');
      return;
    }
    final subj = _uniq('DelTest');
    await _send(2, subject: subj);
    final imap = await connect();
    try {
      final recent = await imap.runExclusive(
          () => imap.fetchRecentMessages('INBOX', count: 50));
      final delUids = recent
          .where((e) => e.subject.startsWith(subj))
          .map((e) => e.uid)
          .toList();
      expect(delUids, hasLength(2));

      // Delete one by one (batch), then empty whatever remains.
      await imap.runExclusive(
          () => imap.deleteMessages('INBOX', [delUids.first]));
      final mid = await imap.runExclusive(
          () => imap.fetchRecentMessages('INBOX', count: 50));
      expect(mid.where((e) => e.subject.startsWith(subj)), hasLength(1));

      final removed =
          await imap.runExclusive(() => imap.emptyFolder('INBOX'));
      expect(removed, greaterThanOrEqualTo(1));

      final empty = await imap.runExclusive(
          () => imap.fetchRecentMessages('INBOX', count: 50));
      expect(empty, isEmpty);
    } finally {
      await imap.disconnect();
    }
  });

  test('listFolders reports the unread count', () async {
    if (!up) {
      markTestSkipped('GreenMail not running on localhost:3143');
      return;
    }
    await _send(2, subject: 'UnreadTest');
    final imap = await connect();
    try {
      final folders = await imap.runExclusive(imap.listFolders);
      final inbox = folders.firstWhere((f) => f.path.toUpperCase() == 'INBOX');
      expect(inbox.unread, greaterThanOrEqualTo(2));
    } finally {
      await imap.disconnect();
    }
  });
}
