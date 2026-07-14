import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import '../models/config.dart';
import '../services/storage_service.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

/// The configured accounts and which one is active.
class AccountsNotifier extends AsyncNotifier<AccountsState> {
  @override
  Future<AccountsState> build() {
    return ref.read(storageServiceProvider).loadAccounts();
  }

  Future<void> _persist(AccountsState next) async {
    await ref.read(storageServiceProvider).saveAccounts(next);
    state = AsyncData(next);
  }

  Future<void> addAccount({
    required MailAccountConfig config,
    required String imapPassword,
    required String smtpPassword,
  }) async {
    final current = state.value ?? const AccountsState();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await ref.read(storageServiceProvider).saveCredentials(
          id,
          imapPassword: imapPassword,
          smtpPassword: smtpPassword,
        );
    await _persist(AccountsState(
      accounts: [...current.accounts, MailAccount(id: id, config: config)],
      currentId: id,
    ));
  }

  /// Updates the active account. Passwords left null/empty keep the
  /// stored values — used when editing settings.
  Future<void> updateCurrent({
    required MailAccountConfig config,
    String? imapPassword,
    String? smtpPassword,
    String? signature,
  }) async {
    final current = state.value?.current;
    if (current == null) return;
    final storage = ref.read(storageServiceProvider);

    final imap = (imapPassword != null && imapPassword.isNotEmpty)
        ? imapPassword
        : await storage.readImapPassword(current.id);
    final smtp = (smtpPassword != null && smtpPassword.isNotEmpty)
        ? smtpPassword
        : await storage.readSmtpPassword(current.id);
    if (imap == null || smtp == null) {
      throw StateError('Mot de passe requis');
    }
    await storage.saveCredentials(current.id,
        imapPassword: imap, smtpPassword: smtp);

    final accountsState = state.value!;
    await _persist(accountsState.copyWith(
      accounts: [
        for (final account in accountsState.accounts)
          if (account.id == current.id)
            account.copyWith(
              config: config,
              signature: signature ?? account.signature,
            )
          else
            account,
      ],
    ));
  }

  /// Deletes the active account (credentials + cached data) and falls
  /// back to the first remaining account.
  Future<void> removeCurrent() async {
    final accountsState = state.value;
    final current = accountsState?.current;
    if (accountsState == null || current == null) return;
    final storage = ref.read(storageServiceProvider);
    await storage.clearCredentials(current.id);
    await storage.deleteAccountData(current.id);

    final remaining = accountsState.accounts
        .where((account) => account.id != current.id)
        .toList();
    await _persist(AccountsState(
      accounts: remaining,
      currentId: remaining.firstOrNull?.id,
    ));
  }

  Future<void> switchTo(String accountId) async {
    final accountsState = state.value;
    if (accountsState == null || accountsState.currentId == accountId) return;
    await _persist(accountsState.copyWith(currentId: accountId));
  }
}

final accountsProvider =
    AsyncNotifierProvider<AccountsNotifier, AccountsState>(
  AccountsNotifier.new,
);

/// The active account, or null before setup.
final currentAccountProvider = Provider<MailAccount?>(
  (ref) => ref.watch(accountsProvider).value?.current,
);

/// Backward-compatible view: the active account's connection settings.
final accountConfigProvider = Provider<AsyncValue<MailAccountConfig?>>(
  (ref) => ref
      .watch(accountsProvider)
      .whenData((state) => state.current?.config),
);
