import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/account.dart';
import '../models/config.dart';
import '../models/email.dart';
import '../models/folder.dart';
import '../models/prefs.dart';

/// Persists everything the app needs locally:
/// - per-account credentials, in encrypted secure storage (never logged)
/// - the account list + active account, as a local JSON file
/// - email metadata, bodies and folder lists in SQLite, scoped by account
class StorageService {
  StorageService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _accountsFileName = 'accounts.json';
  static const _legacyConfigFileName = 'account_config.json';
  static const _legacyAccountId = 'default';

  final FlutterSecureStorage _secureStorage;
  Database? _db;

  // --- Credentials (secure storage, one pair of keys per account) ---------

  Future<void> saveCredentials(
    String accountId, {
    required String imapPassword,
    required String smtpPassword,
  }) async {
    await _secureStorage.write(
        key: 'imap_password_$accountId', value: imapPassword);
    await _secureStorage.write(
        key: 'smtp_password_$accountId', value: smtpPassword);
  }

  Future<String?> readImapPassword(String accountId) =>
      _secureStorage.read(key: 'imap_password_$accountId');

  Future<String?> readSmtpPassword(String accountId) =>
      _secureStorage.read(key: 'smtp_password_$accountId');

  Future<void> clearCredentials(String accountId) async {
    await _secureStorage.delete(key: 'imap_password_$accountId');
    await _secureStorage.delete(key: 'smtp_password_$accountId');
  }

  // --- Accounts file (non-secret) ------------------------------------------

  Future<File> _fileIn(String name) async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, name));
  }

  Future<void> saveAccounts(AccountsState state) async {
    final file = await _fileIn(_accountsFileName);
    await file.writeAsString(jsonEncode(state.toJson()));
  }

  /// Loads the account list, migrating the single-account layout
  /// (account_config.json + un-suffixed keychain keys) if present.
  Future<AccountsState> loadAccounts() async {
    final file = await _fileIn(_accountsFileName);
    if (file.existsSync()) {
      return AccountsState.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    }

    final legacy = await _fileIn(_legacyConfigFileName);
    if (!legacy.existsSync()) return const AccountsState();

    final config = MailAccountConfig.fromJson(
      jsonDecode(await legacy.readAsString()) as Map<String, dynamic>,
    );
    final state = AccountsState(
      accounts: [MailAccount(id: _legacyAccountId, config: config)],
      currentId: _legacyAccountId,
    );
    // Move the legacy (un-suffixed) keychain entries to the new keys.
    final imap = await _secureStorage.read(key: 'imap_password');
    final smtp = await _secureStorage.read(key: 'smtp_password');
    if (imap != null && smtp != null) {
      await saveCredentials(_legacyAccountId,
          imapPassword: imap, smtpPassword: smtp);
      await _secureStorage.delete(key: 'imap_password');
      await _secureStorage.delete(key: 'smtp_password');
    }
    await saveAccounts(state);
    await legacy.delete();
    return state;
  }

  // --- Background watcher state ---------------------------------------------

  /// Per-folder unread counts seen at the last background scan, so the
  /// watcher can detect which folders grew (path → unread).
  Future<Map<String, int>> readFolderUnread() async {
    final file = await _fileIn('folder_unread.json');
    if (!file.existsSync()) return {};
    try {
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return map.map((key, value) => MapEntry(key, (value as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  Future<void> writeFolderUnread(Map<String, int> counts) async {
    final file = await _fileIn('folder_unread.json');
    await file.writeAsString(jsonEncode(counts));
  }

  // --- UI preferences (non-secret) ------------------------------------------

  Future<void> savePrefs(AppPrefs prefs) async {
    final file = await _fileIn('prefs.json');
    await file.writeAsString(jsonEncode(prefs.toJson()));
  }

  Future<AppPrefs> loadPrefs() async {
    final file = await _fileIn('prefs.json');
    if (!file.existsSync()) return const AppPrefs();
    try {
      return AppPrefs.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AppPrefs();
    }
  }

  // --- SQLite: email metadata + folders, scoped by account -----------------

  Future<Database> _database() async {
    final existing = _db;
    if (existing != null) return existing;

    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'openmailbox.db');
    final db = await openDatabase(
      dbPath,
      version: 6,
      onCreate: (db, version) async {
        await db.execute(_createEmailsTable);
        await db.execute(_createFoldersTable);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 4) {
          // v4 scopes both tables by account, which changes their primary
          // keys — SQLite can't alter PKs, and these are pure caches, so
          // rebuild them (they refill on the next sync).
          await db.execute('DROP TABLE IF EXISTS emails');
          await db.execute('DROP TABLE IF EXISTS folders');
          await db.execute(_createEmailsTable);
          await db.execute(_createFoldersTable);
        }
        if (oldVersion < 6) {
          // v6 adds recipients + label keywords. Idempotent.
          final columns = (await db.rawQuery('PRAGMA table_info(emails)'))
              .map((row) => row['name'] as String)
              .toSet();
          if (!columns.contains('recipients')) {
            await db.execute(
                "ALTER TABLE emails ADD COLUMN recipients TEXT NOT NULL DEFAULT ''");
          }
          if (!columns.contains('labels')) {
            await db.execute(
                "ALTER TABLE emails ADD COLUMN labels TEXT NOT NULL DEFAULT ''");
          }
        }
        if (oldVersion < 5) {
          // v5 adds the \Flagged star. Idempotent per the migration rule.
          final columns = (await db.rawQuery('PRAGMA table_info(emails)'))
              .map((row) => row['name'] as String)
              .toSet();
          if (!columns.contains('isFlagged')) {
            await db.execute(
                'ALTER TABLE emails ADD COLUMN isFlagged INTEGER NOT NULL DEFAULT 0');
          }
        }
      },
    );
    _db = db;
    return db;
  }

  static const _createEmailsTable = '''
    CREATE TABLE emails (
      account TEXT NOT NULL,
      uid INTEGER NOT NULL,
      folder TEXT NOT NULL,
      "from" TEXT NOT NULL,
      fromEmail TEXT NOT NULL DEFAULT '',
      subject TEXT NOT NULL,
      date INTEGER NOT NULL,
      preview TEXT NOT NULL,
      isRead INTEGER NOT NULL,
      isFlagged INTEGER NOT NULL DEFAULT 0,
      recipients TEXT NOT NULL DEFAULT '',
      labels TEXT NOT NULL DEFAULT '',
      body TEXT,
      bodyIsHtml INTEGER,
      PRIMARY KEY (account, folder, uid)
    )
  ''';

  static const _createFoldersTable = '''
    CREATE TABLE folders (
      account TEXT NOT NULL,
      path TEXT NOT NULL,
      name TEXT NOT NULL,
      total INTEGER NOT NULL DEFAULT 0,
      unread INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (account, path)
    )
  ''';

  Future<void> saveFolders(String accountId, List<Folder> folders) async {
    final db = await _database();
    final batch = db.batch();
    batch.delete('folders', where: 'account = ?', whereArgs: [accountId]);
    for (final folder in folders) {
      batch.insert('folders', {
        'account': accountId,
        'path': folder.path,
        'name': folder.name,
        'total': folder.total,
        'unread': folder.unread,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<Folder>> loadFolders(String accountId) async {
    final db = await _database();
    final rows = await db
        .query('folders', where: 'account = ?', whereArgs: [accountId]);
    return rows.map((row) {
      return Folder(
        name: row['name']! as String,
        path: row['path']! as String,
        total: (row['total'] as int?) ?? 0,
        unread: (row['unread'] as int?) ?? 0,
      );
    }).toList();
  }

  /// Replaces the cached list of [folder]: metadata is upserted (cached
  /// bodies survive) and rows no longer on the server are removed.
  Future<void> replaceFolderEmails(
      String accountId, String folder, List<Email> emails) async {
    final db = await _database();
    final batch = db.batch();
    if (emails.isEmpty) {
      batch.delete('emails',
          where: 'account = ? AND folder = ?', whereArgs: [accountId, folder]);
    } else {
      // Parameterized placeholders rather than string-interpolated uids —
      // safe today (uid is an int) and robust if the type ever changes.
      final placeholders = List.filled(emails.length, '?').join(',');
      batch.rawDelete(
        'DELETE FROM emails WHERE account = ? AND folder = ? '
        'AND uid NOT IN ($placeholders)',
        [accountId, folder, ...emails.map((e) => e.uid)],
      );
    }
    for (final email in emails) {
      batch.rawInsert(
        '''
        INSERT INTO emails
          (account, uid, folder, "from", fromEmail, subject, date, preview,
           isRead, isFlagged, recipients, labels)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(account, folder, uid) DO UPDATE SET
          "from" = excluded."from",
          fromEmail = excluded.fromEmail,
          subject = excluded.subject,
          date = excluded.date,
          preview = excluded.preview,
          isRead = excluded.isRead,
          isFlagged = excluded.isFlagged,
          recipients = excluded.recipients,
          labels = excluded.labels
        ''',
        [
          accountId,
          email.uid,
          email.folder,
          email.from,
          email.fromEmail,
          email.subject,
          email.date.millisecondsSinceEpoch,
          email.preview,
          email.isRead ? 1 : 0,
          email.isFlagged ? 1 : 0,
          email.to,
          email.labels.join(' '),
        ],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Email>> loadEmails(String accountId, String folder) async {
    final db = await _database();
    final rows = await db.query(
      'emails',
      where: 'account = ? AND folder = ?',
      whereArgs: [accountId, folder],
      orderBy: 'date DESC',
    );
    return rows.map(_emailFromRow).toList();
  }

  Future<void> setRead(
      String accountId, String folder, int uid, bool isRead) async {
    final db = await _database();
    await db.update(
      'emails',
      {'isRead': isRead ? 1 : 0},
      where: 'account = ? AND folder = ? AND uid = ?',
      whereArgs: [accountId, folder, uid],
    );
  }

  Future<void> setLabels(
      String accountId, String folder, int uid, List<String> labels) async {
    final db = await _database();
    await db.update(
      'emails',
      {'labels': labels.join(' ')},
      where: 'account = ? AND folder = ? AND uid = ?',
      whereArgs: [accountId, folder, uid],
    );
  }

  Future<void> setFlagged(
      String accountId, String folder, int uid, bool isFlagged) async {
    final db = await _database();
    await db.update(
      'emails',
      {'isFlagged': isFlagged ? 1 : 0},
      where: 'account = ? AND folder = ? AND uid = ?',
      whereArgs: [accountId, folder, uid],
    );
  }

  Future<void> deleteEmail(String accountId, String folder, int uid) async {
    final db = await _database();
    await db.delete(
      'emails',
      where: 'account = ? AND folder = ? AND uid = ?',
      whereArgs: [accountId, folder, uid],
    );
  }

  /// Removes the cached emails of one folder (folder deleted on server).
  Future<void> deleteAccountFolder(String accountId, String folder) async {
    final db = await _database();
    await db.delete('emails',
        where: 'account = ? AND folder = ?', whereArgs: [accountId, folder]);
  }

  /// Removes every cached row of a deleted account.
  Future<void> deleteAccountData(String accountId) async {
    final db = await _database();
    await db.delete('emails', where: 'account = ?', whereArgs: [accountId]);
    await db.delete('folders', where: 'account = ?', whereArgs: [accountId]);
  }

  // --- Body cache -----------------------------------------------------------

  Future<void> saveBody(String accountId, String folder, int uid, String body,
      {required bool isHtml}) async {
    final db = await _database();
    await db.update(
      'emails',
      {'body': body, 'bodyIsHtml': isHtml ? 1 : 0},
      where: 'account = ? AND folder = ? AND uid = ?',
      whereArgs: [accountId, folder, uid],
    );
  }

  /// Returns the cached body and its HTML-ness, or null if never fetched.
  Future<(String, bool)?> loadBody(
      String accountId, String folder, int uid) async {
    final db = await _database();
    final rows = await db.query(
      'emails',
      columns: ['body', 'bodyIsHtml'],
      where: 'account = ? AND folder = ? AND uid = ?',
      whereArgs: [accountId, folder, uid],
    );
    if (rows.isEmpty) return null;
    final body = rows.first['body'] as String?;
    if (body == null) return null;
    return (body, (rows.first['bodyIsHtml'] as int?) == 1);
  }

  Email _emailFromRow(Map<String, Object?> row) {
    return Email(
      uid: row['uid']! as int,
      folder: row['folder']! as String,
      from: row['from']! as String,
      fromEmail: (row['fromEmail'] as String?) ?? '',
      subject: row['subject']! as String,
      date: DateTime.fromMillisecondsSinceEpoch(row['date']! as int),
      preview: row['preview']! as String,
      isRead: (row['isRead']! as int) == 1,
      isFlagged: ((row['isFlagged'] as int?) ?? 0) == 1,
      to: (row['recipients'] as String?) ?? '',
      labels: ((row['labels'] as String?) ?? '')
          .split(' ')
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }
}
