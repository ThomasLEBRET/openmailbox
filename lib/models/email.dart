import 'package:freezed_annotation/freezed_annotation.dart';

part 'email.freezed.dart';
part 'email.g.dart';

/// Locally cached email metadata. The full body is fetched on demand
/// from IMAP and is never stored here.
@freezed
abstract class Email with _$Email {
  const factory Email({
    /// IMAP UID within [folder].
    required int uid,
    required String folder,

    /// Display name of the sender (falls back to the address).
    required String from,

    /// Bare address of the sender, used for replies.
    @Default('') String fromEmail,
    required String subject,
    required DateTime date,

    /// First ~200 chars of the body, for the list preview.
    required String preview,
    required bool isRead,

    /// IMAP \Flagged — starred/favori.
    @Default(false) bool isFlagged,
  }) = _Email;

  factory Email.fromJson(Map<String, dynamic> json) =>
      _$EmailFromJson(json);
}
