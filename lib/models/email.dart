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
    required String from,
    required String subject,
    required DateTime date,

    /// First ~200 chars of the body, for the list preview.
    required String preview,
    required bool isRead,
  }) = _Email;

  factory Email.fromJson(Map<String, dynamic> json) =>
      _$EmailFromJson(json);
}
