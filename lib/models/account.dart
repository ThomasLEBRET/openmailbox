import 'package:freezed_annotation/freezed_annotation.dart';

import 'config.dart';

part 'account.freezed.dart';
part 'account.g.dart';

/// One configured mailbox. Passwords are NOT here — they live in secure
/// storage under keys derived from [id].
@freezed
abstract class MailAccount with _$MailAccount {
  const MailAccount._();

  const factory MailAccount({
    required String id,
    required MailAccountConfig config,
  }) = _MailAccount;

  factory MailAccount.fromJson(Map<String, dynamic> json) =>
      _$MailAccountFromJson(json);

  /// Shown in the account switcher.
  String get label => config.imap.username;
}

/// Everything persisted about accounts: the list and which one is active.
@freezed
abstract class AccountsState with _$AccountsState {
  const AccountsState._();

  const factory AccountsState({
    @Default([]) List<MailAccount> accounts,
    String? currentId,
  }) = _AccountsState;

  factory AccountsState.fromJson(Map<String, dynamic> json) =>
      _$AccountsStateFromJson(json);

  MailAccount? get current =>
      accounts.where((account) => account.id == currentId).firstOrNull ??
      accounts.firstOrNull;
}
