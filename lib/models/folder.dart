import 'package:freezed_annotation/freezed_annotation.dart';

part 'folder.freezed.dart';
part 'folder.g.dart';

@freezed
abstract class Folder with _$Folder {
  const factory Folder({
    /// Display name, e.g. "Inbox", "Sent".
    required String name,

    /// IMAP path, e.g. "INBOX", "[Gmail]/Sent Mail".
    required String path,

    /// Total number of messages (IMAP STATUS MESSAGES).
    @Default(0) int total,

    /// Number of unseen messages (IMAP STATUS UNSEEN).
    @Default(0) int unread,
  }) = _Folder;

  factory Folder.fromJson(Map<String, dynamic> json) =>
      _$FolderFromJson(json);
}
