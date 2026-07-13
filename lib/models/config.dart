import 'package:freezed_annotation/freezed_annotation.dart';

part 'config.freezed.dart';
part 'config.g.dart';

/// Non-secret connection settings, safe to persist as local JSON.
/// Passwords are never part of this model — see `StorageService` for
/// how credentials are kept in secure storage instead.
@freezed
abstract class ImapConfig with _$ImapConfig {
  const factory ImapConfig({
    required String host,
    required int port,
    required String username,
  }) = _ImapConfig;

  factory ImapConfig.fromJson(Map<String, dynamic> json) =>
      _$ImapConfigFromJson(json);
}

@freezed
abstract class SmtpConfig with _$SmtpConfig {
  const factory SmtpConfig({
    required String host,
    required int port,
    required String username,
  }) = _SmtpConfig;

  factory SmtpConfig.fromJson(Map<String, dynamic> json) =>
      _$SmtpConfigFromJson(json);
}

@freezed
abstract class MailAccountConfig with _$MailAccountConfig {
  const factory MailAccountConfig({
    required ImapConfig imap,
    required SmtpConfig smtp,
  }) = _MailAccountConfig;

  factory MailAccountConfig.fromJson(Map<String, dynamic> json) =>
      _$MailAccountConfigFromJson(json);
}
