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
  }) = _Folder;

  factory Folder.fromJson(Map<String, dynamic> json) =>
      _$FolderFromJson(json);
}
