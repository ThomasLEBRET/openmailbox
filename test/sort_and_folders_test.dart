import 'package:flutter_test/flutter_test.dart';
import 'package:openmailbox/models/email.dart';
import 'package:openmailbox/models/folder.dart';
import 'package:openmailbox/models/prefs.dart';
import 'package:openmailbox/providers/folder_provider.dart';

Email _email({
  required int uid,
  required String from,
  required DateTime date,
  bool isRead = true,
}) =>
    Email(
      uid: uid,
      folder: 'INBOX',
      from: from,
      subject: 'sujet $uid',
      date: date,
      preview: '',
      isRead: isRead,
    );

void main() {
  final d = DateTime(2026, 1, 1);
  final emails = [
    _email(uid: 1, from: 'Charlie', date: d.add(const Duration(days: 1)), isRead: true),
    _email(uid: 2, from: 'alice', date: d.add(const Duration(days: 3)), isRead: false),
    _email(uid: 3, from: 'Bob', date: d.add(const Duration(days: 2)), isRead: true),
  ];

  group('SortMode.apply', () {
    test('dateDesc: newest first', () {
      final r = SortMode.dateDesc.apply(emails);
      expect(r.map((e) => e.uid), [2, 3, 1]);
    });

    test('dateAsc: oldest first', () {
      final r = SortMode.dateAsc.apply(emails);
      expect(r.map((e) => e.uid), [1, 3, 2]);
    });

    test('unreadFirst: unread on top, then by date desc', () {
      final r = SortMode.unreadFirst.apply(emails);
      expect(r.first.uid, 2); // the only unread
      // remaining are read, newest first
      expect(r.map((e) => e.uid), [2, 3, 1]);
    });

    test('sender: alphabetical, case-insensitive', () {
      final r = SortMode.sender.apply(emails);
      expect(r.map((e) => e.from), ['alice', 'Bob', 'Charlie']);
    });

    test('does not mutate the input list', () {
      final input = [...emails];
      SortMode.dateAsc.apply(input);
      expect(input.map((e) => e.uid), [1, 2, 3]);
    });

    test('fromName falls back to dateDesc on unknown', () {
      expect(SortMode.fromName('bogus'), SortMode.dateDesc);
    });
  });

  group('findTrashPath', () {
    Folder f(String path, String name) => Folder(name: name, path: path);

    test('prefers lowercase system "trash"', () {
      final folders = [f('INBOX', 'Inbox'), f('Trash', 'Trash'), f('trash', 'trash')];
      expect(findTrashPath(folders), 'trash');
    });

    test('matches French "Corbeille" by name', () {
      final folders = [f('INBOX', 'Inbox'), f('X', 'Corbeille')];
      expect(findTrashPath(folders), 'X');
    });

    test('returns null when no trash-like folder', () {
      final folders = [f('INBOX', 'Inbox'), f('Sent', 'Envoyés')];
      expect(findTrashPath(folders), isNull);
    });
  });
}
