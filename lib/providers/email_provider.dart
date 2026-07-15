import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/email.dart';
import 'config_provider.dart';
import 'folder_provider.dart';
import 'imap_session.dart';
import 'undo_provider.dart';

/// True while a server sync of the email list is in flight. Drives the
/// header spinner without blanking the cached list.
class EmailSyncingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final emailSyncingProvider =
    NotifierProvider<EmailSyncingNotifier, bool>(EmailSyncingNotifier.new);

/// Email list for the currently selected folder ([currentFolderProvider]).
class EmailListNotifier extends AsyncNotifier<List<Email>> {
  /// The active account id, or throws before setup.
  String get _accountId {
    final account = ref.read(currentAccountProvider);
    if (account == null) throw StateError('Aucun compte configuré');
    return account.id;
  }

  @override
  Future<List<Email>> build() async {
    final account = ref.watch(currentAccountProvider);
    final folder = ref.watch(currentFolderProvider);
    if (account == null) return const [];
    final storage = ref.read(storageServiceProvider);
    return storage.loadEmails(account.id, folder);
  }

  /// Pulls the latest messages for the current folder and refreshes the
  /// local cache. The cached list stays visible while the sync runs —
  /// blanking it to a spinner made every refresh feel slow.
  Future<void> sync() async {
    ref.read(emailSyncingProvider.notifier).set(true);
    try {
      final accountId = _accountId;
      final folder = ref.read(currentFolderProvider);
      final result = await AsyncValue.guard(() async {
        final emails = await withImapSession(
            ref, (imap) => imap.fetchRecentMessages(folder));
        emails.sort((a, b) => b.date.compareTo(a.date));
        await ref
            .read(storageServiceProvider)
            .replaceFolderEmails(accountId, folder, emails);
        return emails;
      });
      // The user may have switched folder or account while this sync ran —
      // a stale result must not overwrite the current list.
      if (ref.read(currentFolderProvider) == folder &&
          ref.read(currentAccountProvider)?.id == accountId) {
        state = result;
      }
    } finally {
      ref.read(emailSyncingProvider.notifier).set(false);
    }
  }

  /// Server-side search in the current folder — results replace the list
  /// until the next sync() (triggered by clearing the search).
  Future<void> searchServer(String query) async {
    ref.read(emailSyncingProvider.notifier).set(true);
    try {
      final folder = ref.read(currentFolderProvider);
      final result = await AsyncValue.guard(() async {
        final emails = await withImapSession(
            ref, (imap) => imap.searchMessages(folder, query));
        emails.sort((a, b) => b.date.compareTo(a.date));
        return emails;
      });
      if (ref.read(currentFolderProvider) == folder) {
        state = result;
      }
    } finally {
      ref.read(emailSyncingProvider.notifier).set(false);
    }
  }

  /// Some senders declare HTML content as text/plain; without this the
  /// reader shows raw HTML source as text.
  static bool _looksLikeHtml(String body) {
    final head = body.trimLeft().toLowerCase();
    return head.startsWith('<!doctype') || head.startsWith('<html');
  }

  /// Returns the readable body of one email and whether it is HTML.
  /// Bodies are cached in SQLite: re-opening an email is instant.
  Future<(String, bool)> fetchBody(Email email) async {
    final accountId = _accountId;
    final storage = ref.read(storageServiceProvider);
    final cached = await storage.loadBody(accountId, email.folder, email.uid);
    if (cached != null) {
      final (body, isHtml) = cached;
      if (!isHtml && _looksLikeHtml(body)) {
        // Heal rows cached with a wrong flag by earlier versions.
        await storage.saveBody(accountId, email.folder, email.uid, body,
            isHtml: true);
        return (body, true);
      }
      return cached;
    }

    final (message, htmlPartFetched) = await withImapSession(
        ref, (imap) => imap.fetchMessageText(email.folder, email.uid));

    String body;
    bool isHtml;
    if (htmlPartFetched == true) {
      body = message.decodeTextHtmlPart() ??
          message.decodeTextPlainPart() ??
          '(corps vide)';
      isHtml = true;
    } else {
      final html = htmlPartFetched == null ? message.decodeTextHtmlPart() : null;
      if (html != null) {
        body = html;
        isHtml = true;
      } else {
        body = message.decodeTextPlainPart() ??
            message.decodeTextHtmlPart() ??
            '(corps vide)';
        isHtml = _looksLikeHtml(body);
      }
    }
    await storage.saveBody(accountId, email.folder, email.uid, body,
        isHtml: isHtml);
    return (body, isHtml);
  }

  /// Marks locally (snappy UI), then pushes the \Seen flag to the server
  /// best-effort in the background — the next sync reconciles if it fails.
  Future<void> markRead(int uid, bool isRead, {bool recordUndo = true}) async {
    final folder = ref.read(currentFolderProvider);
    final previous = state.value
        ?.where((email) => email.uid == uid)
        .firstOrNull
        ?.isRead;
    if (previous == null || previous == isRead) return;
    await _applyRead(folder, uid, isRead);
    if (recordUndo) {
      ref.read(undoProvider.notifier).push(
          isRead ? 'Marquer lu' : 'Marquer non lu',
          () => _applyRead(folder, uid, previous));
    }
  }

  Future<void> _applyRead(String folder, int uid, bool isRead) async {
    final accountId = _accountId;
    await ref
        .read(storageServiceProvider)
        .setRead(accountId, folder, uid, isRead);
    if (ref.read(currentFolderProvider) == folder) {
      state = state.whenData(
        (emails) => [
          for (final email in emails)
            if (email.uid == uid) email.copyWith(isRead: isRead) else email,
        ],
      );
    }
    // Counters and server flag update happen in the background: awaiting
    // the IMAP round trip here is what made read-toggles feel laggy.
    unawaited(ref
        .read(folderListProvider.notifier)
        .adjustCounts(folder, unreadDelta: isRead ? -1 : 1));
    unawaited(withImapSession(
            ref, (imap) => imap.markSeen(folder, uid, isSeen: isRead))
        .catchError((_) {}));
  }

  /// Toggles the star locally then pushes \Flagged in the background.
  Future<void> toggleFlagged(int uid, {bool recordUndo = true}) async {
    final folder = ref.read(currentFolderProvider);
    final email = state.value?.where((e) => e.uid == uid).firstOrNull;
    if (email == null) return;
    final flagged = !email.isFlagged;
    await _applyFlag(folder, uid, flagged);
    if (recordUndo) {
      ref.read(undoProvider.notifier).push(
          flagged ? 'Étoile' : 'Étoile retirée',
          () => _applyFlag(folder, uid, !flagged));
    }
  }

  Future<void> _applyFlag(String folder, int uid, bool flagged) async {
    final accountId = _accountId;
    await ref
        .read(storageServiceProvider)
        .setFlagged(accountId, folder, uid, flagged);
    if (ref.read(currentFolderProvider) == folder) {
      state = state.whenData(
        (emails) => [
          for (final e in emails)
            if (e.uid == uid) e.copyWith(isFlagged: flagged) else e,
        ],
      );
    }
    unawaited(withImapSession(
            ref, (imap) => imap.setFlagged(folder, uid, isFlagged: flagged))
        .catchError((_) {}));
  }

  /// Moves an email of the current folder to [targetPath] (drag & drop,
  /// deletion-to-trash). Optimistic with rollback; records a Cmd+Z entry
  /// when the server reports the new UID (COPYUID).
  Future<void> moveToFolder(int uid, String targetPath,
      {String undoLabel = 'Déplacement', bool recordUndo = true}) async {
    final accountId = _accountId;
    final folder = ref.read(currentFolderProvider);
    if (folder == targetPath) return;
    final storage = ref.read(storageServiceProvider);
    final emails = state.value ?? const <Email>[];
    final removed = emails.where((email) => email.uid == uid).firstOrNull;
    if (removed == null) return;
    final wasUnread = !removed.isRead;
    final folderNotifier = ref.read(folderListProvider.notifier);

    Future<void> shiftCounts(int direction) async {
      await folderNotifier.adjustCounts(
        folder,
        totalDelta: -direction,
        unreadDelta: wasUnread ? -direction : 0,
      );
      await folderNotifier.adjustCounts(
        targetPath,
        totalDelta: direction,
        unreadDelta: wasUnread ? direction : 0,
      );
    }

    // Optimistic local removal.
    state = AsyncData(
        emails.where((email) => email.uid != uid).toList(growable: false));
    await storage.deleteEmail(accountId, folder, uid);
    unawaited(shiftCounts(1));

    final int? newUid;
    try {
      newUid = await withImapSession(
          ref, (imap) => imap.moveMessage(folder, uid, targetPath));
    } catch (_) {
      // Roll back: restore the email and the counts.
      final current = state.value ?? const <Email>[];
      final restored = [...current, removed]
        ..sort((a, b) => b.date.compareTo(a.date));
      if (ref.read(currentFolderProvider) == folder) {
        state = AsyncData(restored);
      }
      await storage.replaceFolderEmails(accountId, folder, restored);
      unawaited(shiftCounts(-1));
      rethrow;
    }

    final movedUid = newUid;
    if (recordUndo && movedUid != null) {
      ref.read(undoProvider.notifier).push(undoLabel, () async {
        await withImapSession(
            ref, (imap) => imap.moveMessage(targetPath, movedUid, folder));
        unawaited(shiftCounts(-1));
        // Refresh whichever of the two folders is on screen.
        final visible = ref.read(currentFolderProvider);
        if (visible == folder || visible == targetPath) {
          unawaited(sync());
        }
      });
    }
  }

  /// Moves the email to the trash folder (or deletes permanently when
  /// already in the trash — not undoable). Returns true when it was
  /// moved to the trash.
  Future<bool> deleteEmail(int uid) async {
    final accountId = _accountId;
    final folder = ref.read(currentFolderProvider);
    final folders = ref.read(folderListProvider).value ?? const [];
    final trashPath = findTrashPath(folders);

    if (trashPath != null && folder != trashPath) {
      await moveToFolder(uid, trashPath, undoLabel: 'Suppression');
      return true;
    }

    // Permanent deletion inside the trash (or no trash folder found).
    final storage = ref.read(storageServiceProvider);
    final emails = state.value ?? const <Email>[];
    final removed = emails.where((email) => email.uid == uid).firstOrNull;
    if (removed == null) return false;
    final wasUnread = !removed.isRead;
    final folderNotifier = ref.read(folderListProvider.notifier);

    state = AsyncData(
        emails.where((email) => email.uid != uid).toList(growable: false));
    await storage.deleteEmail(accountId, folder, uid);
    unawaited(folderNotifier.adjustCounts(
      folder,
      totalDelta: -1,
      unreadDelta: wasUnread ? -1 : 0,
    ));

    try {
      await withImapSession(ref, (imap) => imap.deleteMessage(folder, uid));
    } catch (_) {
      final current = state.value ?? const <Email>[];
      final restored = [...current, removed]
        ..sort((a, b) => b.date.compareTo(a.date));
      state = AsyncData(restored);
      await storage.replaceFolderEmails(accountId, folder, restored);
      unawaited(folderNotifier.adjustCounts(
        folder,
        totalDelta: 1,
        unreadDelta: wasUnread ? 1 : 0,
      ));
      rethrow;
    }
    return false;
  }
}

final emailListProvider =
    AsyncNotifierProvider<EmailListNotifier, List<Email>>(
  EmailListNotifier.new,
);
