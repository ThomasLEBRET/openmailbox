import 'package:enough_mail/enough_mail.dart' show ImapClient;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openmailbox/models/account.dart';
import 'package:openmailbox/models/config.dart';
import 'package:openmailbox/models/email.dart';
import 'package:openmailbox/models/folder.dart';
import 'package:openmailbox/providers/config_provider.dart';
import 'package:openmailbox/providers/email_provider.dart';
import 'package:openmailbox/providers/folder_provider.dart';
import 'package:openmailbox/providers/imap_session.dart';
import 'package:openmailbox/services/imap_service.dart';
import 'package:openmailbox/services/storage_service.dart';

/// In-memory StorageService — no sqflite, no secure storage, no disk.
class FakeStorage extends StorageService {
  FakeStorage(this.emailsByFolder, this.folders);

  final Map<String, List<Email>> emailsByFolder;
  final List<Folder> folders;

  @override
  Future<String?> readImapPassword(String accountId) async => 'pw';

  @override
  Future<List<Email>> loadEmails(String accountId, String folder) async =>
      List.of(emailsByFolder[folder] ?? const []);

  @override
  Future<List<Folder>> loadFolders(String accountId) async => List.of(folders);

  @override
  Future<void> saveFolders(String accountId, List<Folder> folders) async {}

  @override
  Future<void> deleteEmail(String accountId, String folder, int uid) async {
    emailsByFolder[folder]?.removeWhere((e) => e.uid == uid);
  }

  @override
  Future<void> replaceFolderEmails(
      String accountId, String folder, List<Email> emails) async {
    emailsByFolder[folder] = List.of(emails);
  }
}

/// Fake IMAP that records calls and can be told to fail, so rollback paths
/// are exercised without a real server.
class FakeImap extends ImapService {
  bool shouldFail = false;
  final List<(String, List<int>, String)> moves = [];
  final List<(String, List<int>)> deletes = [];

  @override
  Future<T> runExclusive<T>(Future<T> Function() fn) => fn();

  @override
  Future<ImapClient> ensureConnected(ImapConfig config, String password) async =>
      ImapClient(isLogEnabled: false);

  @override
  Future<int?> moveMessage(String folder, int uid, String target) async {
    if (shouldFail) throw Exception('boom');
    moves.add((folder, [uid], target));
    return uid; // pretend COPYUID returned the same id
  }

  @override
  Future<void> moveMessages(
      String folder, List<int> uids, String target) async {
    if (shouldFail) throw Exception('boom');
    moves.add((folder, uids, target));
  }

  @override
  Future<void> deleteMessage(String folder, int uid) async {
    if (shouldFail) throw Exception('boom');
    deletes.add((folder, [uid]));
  }

  @override
  Future<void> deleteMessages(String folder, List<int> uids) async {
    if (shouldFail) throw Exception('boom');
    deletes.add((folder, uids));
  }
}

Email _mail(int uid, {String folder = 'INBOX', bool isRead = true}) => Email(
      uid: uid,
      folder: folder,
      from: 'Sender $uid',
      subject: 'Subject $uid',
      date: DateTime(2026, 1, uid),
      preview: '',
      isRead: isRead,
    );

ProviderContainer _container(FakeStorage storage, FakeImap imap) {
  const account = MailAccount(
    id: 'acc',
    config: MailAccountConfig(
      imap: ImapConfig(host: 'localhost', port: 993, username: 'u'),
      smtp: SmtpConfig(host: 'localhost', port: 465, username: 'u'),
    ),
  );
  return ProviderContainer(overrides: [
    storageServiceProvider.overrideWithValue(storage),
    imapServiceProvider.overrideWithValue(imap),
    imapBackgroundServiceProvider.overrideWithValue(imap),
    currentAccountProvider.overrideWithValue(account),
  ]);
}

List<int> _uids(ProviderContainer c) =>
    (c.read(emailListProvider).value ?? const []).map((e) => e.uid).toList();

void main() {
  const inbox = 'INBOX';
  const trash = 'trash';
  final folders = [
    const Folder(name: 'Inbox', path: inbox),
    const Folder(name: 'Corbeille', path: trash),
  ];

  Future<ProviderContainer> setup(FakeImap imap,
      {Map<String, List<Email>>? seed}) async {
    final storage = FakeStorage(
      seed ??
          {
            inbox: [_mail(1), _mail(2, isRead: false), _mail(3)],
            trash: [],
          },
      folders,
    );
    final c = _container(storage, imap);
    await c.read(folderListProvider.future);
    await c.read(emailListProvider.future);
    return c;
  }

  test('delete moves the email to trash and removes it from the list', () async {
    final imap = FakeImap();
    final c = await setup(imap);

    final movedToTrash =
        await c.read(emailListProvider.notifier).deleteEmail(2);

    expect(movedToTrash, isTrue);
    expect(_uids(c), [1, 3]); // 2 gone from the inbox list
    expect(imap.moves, hasLength(1));
    expect(imap.moves.single.$1, inbox);
    expect(imap.moves.single.$2, [2]);
    expect(imap.moves.single.$3, trash);
  });

  test('delete rolls back and rethrows when the server MOVE fails', () async {
    final imap = FakeImap()..shouldFail = true;
    final c = await setup(imap);

    await expectLater(
      c.read(emailListProvider.notifier).deleteEmail(2),
      throwsA(isA<Exception>()),
    );
    // The email must be restored — this is exactly the "reappear" guarantee.
    expect(_uids(c)..sort(), [1, 2, 3]);
  });

  test('permanent delete inside trash calls deleteMessage, not move', () async {
    final imap = FakeImap();
    final c = await setup(imap, seed: {
      inbox: [],
      trash: [_mail(10, folder: trash), _mail(11, folder: trash)],
    });
    c.read(currentFolderProvider.notifier).select(trash);
    await c.read(emailListProvider.future);

    final movedToTrash =
        await c.read(emailListProvider.notifier).deleteEmail(10);

    expect(movedToTrash, isFalse);
    expect(imap.deletes.single.$1, trash);
    expect(imap.deletes.single.$2, [10]);
    expect(imap.moves, isEmpty);
  });

  test('deleteMany moves all selected in a single batch call', () async {
    final imap = FakeImap();
    final c = await setup(imap);

    await c.read(emailListProvider.notifier).deleteMany([1, 3]);

    expect(_uids(c), [2]);
    expect(imap.moves, hasLength(1)); // ONE round trip, not two
    expect(imap.moves.single.$2..sort(), [1, 3]);
    expect(imap.moves.single.$3, trash);
  });

  test('deleteMany rolls back the whole batch on failure', () async {
    final imap = FakeImap()..shouldFail = true;
    final c = await setup(imap);

    await expectLater(
      c.read(emailListProvider.notifier).deleteMany([1, 3]),
      throwsA(isA<Exception>()),
    );
    expect(_uids(c)..sort(), [1, 2, 3]);
  });

  test('moveMany moves selected to an arbitrary folder', () async {
    final imap = FakeImap();
    final c = await setup(imap);

    await c.read(emailListProvider.notifier).moveMany([2], trash);

    expect(_uids(c), [1, 3]);
    expect(imap.moves.single.$1, inbox);
    expect(imap.moves.single.$2, [2]);
    expect(imap.moves.single.$3, trash);
  });
}
