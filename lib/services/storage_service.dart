import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/config.dart';
import '../models/email.dart';
import '../models/folder.dart';

/// Persists everything the app needs locally:
/// - account credentials, in encrypted secure storage (never logged/exported)
/// - non-secret connection settings, as a local JSON file
/// - email metadata and folder list, in SQLite (bodies are fetched on demand)
class StorageService {
  StorageService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _imapPasswordKey = 'imap_password';
  static const _smtpPasswordKey = 'smtp_password';
  static const _configFileName = 'account_config.json';

  final FlutterSecureStorage _secureStorage;
  Database? _db;

  // --- Credentials (secure storage) ---------------------------------------

  Future<void> saveCredentials({
    required String imapPassword,
    required String smtpPassword,
  }) async {
    await _secureStorage.write(key: _imapPasswordKey, value: imapPassword);
    await _secureStorage.write(key: _smtpPasswordKey, value: smtpPassword);
  }

  Future<String?> readImapPassword() =>
      _secureStorage.read(key: _imapPasswordKey);

  Future<String?> readSmtpPassword() =>
      _secureStorage.read(key: _smtpPasswordKey);

  Future<void> clearCredentials() async {
    await _secureStorage.delete(key: _imapPasswordKey);
    await _secureStorage.delete(key: _smtpPasswordKey);
  }

  // --- Non-secret config (local JSON file) --------------------------------

  Future<File> _configFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _configFileName));
  }

  Future<void> saveAccountConfig(MailAccountConfig config) async {
    final file = await _configFile();
    await file.writeAsString(jsonEncode(config.toJson()));
  }

  Future<MailAccountConfig?> loadAccountConfig() async {
    final file = await _configFile();
    if (!file.existsSync()) return null;
    final content = await file.readAsString();
    return MailAccountConfig.fromJson(
      jsonDecode(content) as Map<String, dynamic>,
    );
  }

  Future<void> clearAccountConfig() async {
    final file = await _configFile();
    if (file.existsSync()) await file.delete();
  }

  // --- SQLite: email metadata + folders -----------------------------------

  Future<Database> _database() async {
    final existing = _db;
    if (existing != null) return existing;

    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'openmailbox.db');
    final db = await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE emails (
            uid INTEGER NOT NULL,
            folder TEXT NOT NULL,
            "from" TEXT NOT NULL,
            fromEmail TEXT NOT NULL DEFAULT '',
            subject TEXT NOT NULL,
            date INTEGER NOT NULL,
            preview TEXT NOT NULL,
            isRead INTEGER NOT NULL,
            body TEXT,
            bodyIsHtml INTEGER,
            PRIMARY KEY (uid, folder)
          )
        ''');
        await db.execute(_createFoldersTable);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // v2 added total/unread counts; the table is a pure cache,
          // safe to rebuild from the next sync.
          await db.execute('DROP TABLE IF EXISTS folders');
          await db.execute(_createFoldersTable);
        }
        if (oldVersion < 3) {
          // v3 caches fetched message bodies for instant re-opening and
          // stores the sender's bare address for replies.
          await db.execute('ALTER TABLE emails ADD COLUMN body TEXT');
          await db.execute('ALTER TABLE emails ADD COLUMN bodyIsHtml INTEGER');
          await db.execute(
              "ALTER TABLE emails ADD COLUMN fromEmail TEXT NOT NULL DEFAULT ''");
        }
      },
    );
    _db = db;
    return db;
  }

  static const _createFoldersTable = '''
    CREATE TABLE folders (
      path TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      total INTEGER NOT NULL DEFAULT 0,
      unread INTEGER NOT NULL DEFAULT 0
    )
  ''';

  Future<void> saveFolders(List<Folder> folders) async {
    final db = await _database();
    final batch = db.batch();
    batch.delete('folders');
    for (final folder in folders) {
      batch.insert('folders', {
        'path': folder.path,
        'name': folder.name,
        'total': folder.total,
        'unread': folder.unread,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<Folder>> loadFolders() async {
    final db = await _database();
    final rows = await db.query('folders');
    return rows.map((row) {
      return Folder(
        name: row['name']! as String,
        path: row['path']! as String,
        total: (row['total'] as int?) ?? 0,
        unread: (row['unread'] as int?) ?? 0,
      );
    }).toList();
  }

  /// Replaces the cached list of [folder] with [emails]: metadata is
  /// upserted (cached bodies survive) and rows no longer on the server
  /// are removed.
  Future<void> replaceFolderEmails(String folder, List<Email> emails) async {
    final db = await _database();
    final batch = db.batch();
    if (emails.isEmpty) {
      batch.delete('emails', where: 'folder = ?', whereArgs: [folder]);
    } else {
      final uids = emails.map((e) => e.uid).join(',');
      batch.rawDelete(
        'DELETE FROM emails WHERE folder = ? AND uid NOT IN ($uids)',
        [folder],
      );
    }
    for (final email in emails) {
      batch.rawInsert(
        '''
        INSERT INTO emails
          (uid, folder, "from", fromEmail, subject, date, preview, isRead)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(uid, folder) DO UPDATE SET
          "from" = excluded."from",
          fromEmail = excluded.fromEmail,
          subject = excluded.subject,
          date = excluded.date,
          preview = excluded.preview,
          isRead = excluded.isRead
        ''',
        [
          email.uid,
          email.folder,
          email.from,
          email.fromEmail,
          email.subject,
          email.date.millisecondsSinceEpoch,
          email.preview,
          email.isRead ? 1 : 0,
        ],
      );
    }
    await batch.commit(noResult: true);
  }

  // --- Body cache ----------------------------------------------------------

  Future<void> saveBody(
      String folder, int uid, String body, {required bool isHtml}) async {
    final db = await _database();
    await db.update(
      'emails',
      {'body': body, 'bodyIsHtml': isHtml ? 1 : 0},
      where: 'folder = ? AND uid = ?',
      whereArgs: [folder, uid],
    );
  }

  /// Returns the cached body and its HTML-ness, or null if never fetched.
  Future<(String, bool)?> loadBody(String folder, int uid) async {
    final db = await _database();
    final rows = await db.query(
      'emails',
      columns: ['body', 'bodyIsHtml'],
      where: 'folder = ? AND uid = ?',
      whereArgs: [folder, uid],
    );
    if (rows.isEmpty) return null;
    final body = rows.first['body'] as String?;
    if (body == null) return null;
    return (body, (rows.first['bodyIsHtml'] as int?) == 1);
  }

  Future<List<Email>> loadEmails(String folder) async {
    final db = await _database();
    final rows = await db.query(
      'emails',
      where: 'folder = ?',
      whereArgs: [folder],
      orderBy: 'date DESC',
    );
    return rows.map(_emailFromRow).toList();
  }

  Future<void> setRead(String folder, int uid, bool isRead) async {
    final db = await _database();
    await db.update(
      'emails',
      {'isRead': isRead ? 1 : 0},
      where: 'folder = ? AND uid = ?',
      whereArgs: [folder, uid],
    );
  }

  Future<void> deleteEmail(String folder, int uid) async {
    final db = await _database();
    await db.delete(
      'emails',
      where: 'folder = ? AND uid = ?',
      whereArgs: [folder, uid],
    );
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
    );
  }
}
