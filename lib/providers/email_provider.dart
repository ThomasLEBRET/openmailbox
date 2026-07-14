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
      state = await AsyncValue.guard(() async {
        final emails = await withImapSession(
            ref, (imap) => imap.fetchRecentMessages(folder));
        await ref.read(storageServiceProvider).saveEmails(emails);
        return emails;
      });
    } finally {
      ref.read(emailSyncingProvider.notifier).set(false);
    }
  }

  /// Fetches the readable text of one email for the reader panel.
  Future<String> fetchBody(Email email) async {
    final message = await withImapSession(
        ref, (imap) => imap.fetchMessageText(email.folder, email.uid));
    return message.decodeTextPlainPart() ??
        message.decodeTextHtmlPart() ??
        '(corps vide)';
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
  /// already in the trash). Server-first: throws on failure so the caller
  /// can surface it. Both folders' counts are adjusted locally.
  Future<void> deleteEmail(int uid) async {
    final folder = ref.read(currentFolderProvider);
    final storage = ref.read(storageServiceProvider);
    final wasUnread = state.value
            ?.where((email) => email.uid == uid)
            .firstOrNull
            ?.isRead ==
        false;

    final folders = ref.read(folderListProvider).value ?? const [];
    final trashPath = findTrashPath(folders);
    final movesToTrash = trashPath != null && folder != trashPath;

    if (movesToTrash) {
      await withImapSession(
          ref, (imap) => imap.moveToTrash(folder, uid, trashPath));
    } else {
      await withImapSession(ref, (imap) => imap.deleteMessage(folder, uid));
    }

    await storage.deleteEmail(folder, uid);
    state = state.whenData(
      (emails) => emails.where((email) => email.uid != uid).toList(),
    );

    final folderNotifier = ref.read(folderListProvider.notifier);
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
  }
}

final emailListProvider =
    AsyncNotifierProvider<EmailListNotifier, List<Email>>(
  EmailListNotifier.new,
);
