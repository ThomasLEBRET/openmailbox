import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/email.dart';
import 'config_provider.dart';
import 'folder_provider.dart';
import 'imap_session.dart';

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
  @override
  Future<List<Email>> build() async {
    final folder = ref.watch(currentFolderProvider);
    final storage = ref.read(storageServiceProvider);
    return storage.loadEmails(folder);
  }

  /// Pulls the latest messages for the current folder and refreshes the
  /// local cache. The cached list stays visible while the sync runs —
  /// blanking it to a spinner made every refresh feel slow.
  Future<void> sync() async {
    ref.read(emailSyncingProvider.notifier).set(true);
    try {
      final folder = ref.read(currentFolderProvider);
      final result = await AsyncValue.guard(() async {
        final emails = await withImapSession(
            ref, (imap) => imap.fetchRecentMessages(folder));
        emails.sort((a, b) => b.date.compareTo(a.date));
        await ref
            .read(storageServiceProvider)
            .replaceFolderEmails(folder, emails);
        return emails;
      });
      // The user may have switched folders while this sync ran — a stale
      // result must not overwrite the newly selected folder's list.
      if (ref.read(currentFolderProvider) == folder) {
        state = result;
      }
    } finally {
      ref.read(emailSyncingProvider.notifier).set(false);
    }
  }

  /// Returns the readable body of one email and whether it is HTML.
  /// Bodies are cached in SQLite: re-opening an email is instant.
  Future<(String, bool)> fetchBody(Email email) async {
    final storage = ref.read(storageServiceProvider);
    final cached = await storage.loadBody(email.folder, email.uid);
    if (cached != null) return cached;

    final message = await withImapSession(
        ref, (imap) => imap.fetchMessageText(email.folder, email.uid));
    final html = message.decodeTextHtmlPart();
    final (body, isHtml) = html != null
        ? (html, true)
        : (message.decodeTextPlainPart() ?? '(corps vide)', false);
    await storage.saveBody(email.folder, email.uid, body, isHtml: isHtml);
    return (body, isHtml);
  }

  /// Marks locally (snappy UI), then pushes the \Seen flag to the server
  /// best-effort — the next sync reconciles if it fails.
  Future<void> markRead(int uid, bool isRead) async {
    final folder = ref.read(currentFolderProvider);
    final storage = ref.read(storageServiceProvider);
    final previous = state.value
        ?.where((email) => email.uid == uid)
        .firstOrNull
        ?.isRead;
    await storage.setRead(folder, uid, isRead);
    state = state.whenData(
      (emails) => [
        for (final email in emails)
          if (email.uid == uid) email.copyWith(isRead: isRead) else email,
      ],
    );
    if (previous != null && previous != isRead) {
      await ref
          .read(folderListProvider.notifier)
          .adjustCounts(folder, unreadDelta: isRead ? -1 : 1);
    }
    try {
      await withImapSession(
          ref, (imap) => imap.markSeen(folder, uid, isSeen: isRead));
    } catch (_) {
      // Best-effort; local state stays, next sync reconciles.
    }
  }

  /// Moves the email to the trash folder (or deletes permanently when
  /// already in the trash). Optimistic: the email leaves the list and the
  /// counts shift immediately; if the server call then fails, everything
  /// is restored and the error rethrown for the caller to surface.
  ///
  /// Returns true when the email was moved to the trash, false when it
  /// was permanently deleted.
  Future<bool> deleteEmail(int uid) async {
    final folder = ref.read(currentFolderProvider);
    final storage = ref.read(storageServiceProvider);
    final emails = state.value ?? const <Email>[];
    final removed = emails.where((email) => email.uid == uid).firstOrNull;
    if (removed == null) return false;
    final wasUnread = !removed.isRead;

    final folders = ref.read(folderListProvider).value ?? const [];
    final trashPath = findTrashPath(folders);
    final movesToTrash = trashPath != null && folder != trashPath;
    final folderNotifier = ref.read(folderListProvider.notifier);

    // Optimistic local removal.
    state = AsyncData(
        emails.where((email) => email.uid != uid).toList(growable: false));
    await storage.deleteEmail(folder, uid);
    await folderNotifier.adjustCounts(
      folder,
      totalDelta: -1,
      unreadDelta: wasUnread ? -1 : 0,
    );
    if (movesToTrash) {
      await folderNotifier.adjustCounts(
        trashPath,
        totalDelta: 1,
        unreadDelta: wasUnread ? 1 : 0,
      );
    }

    try {
      if (movesToTrash) {
        await withImapSession(
            ref, (imap) => imap.moveToTrash(folder, uid, trashPath));
      } else {
        await withImapSession(
            ref, (imap) => imap.deleteMessage(folder, uid));
      }
    } catch (_) {
      // Roll back: restore the email and the counts.
      final current = state.value ?? const <Email>[];
      final restored = [...current, removed]
        ..sort((a, b) => b.date.compareTo(a.date));
      state = AsyncData(restored);
      await storage.replaceFolderEmails(folder, restored);
      await folderNotifier.adjustCounts(
        folder,
        totalDelta: 1,
        unreadDelta: wasUnread ? 1 : 0,
      );
      if (movesToTrash) {
        await folderNotifier.adjustCounts(
          trashPath,
          totalDelta: -1,
          unreadDelta: wasUnread ? -1 : 0,
        );
      }
      rethrow;
    }
    return movesToTrash;
  }
}

final emailListProvider =
    AsyncNotifierProvider<EmailListNotifier, List<Email>>(
  EmailListNotifier.new,
);
