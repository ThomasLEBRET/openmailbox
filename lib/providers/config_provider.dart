import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/config.dart';
import '../services/storage_service.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

/// Holds the currently configured account (null until setup is completed).
class AccountConfigNotifier extends AsyncNotifier<MailAccountConfig?> {
  @override
  Future<MailAccountConfig?> build() {
    return ref.read(storageServiceProvider).loadAccountConfig();
  }

  /// Persists the account. Passwords left null (or empty) keep the
  /// currently stored value — used when editing settings.
  Future<void> save({
    required MailAccountConfig config,
    String? imapPassword,
    String? smtpPassword,
  }) async {
    final storage = ref.read(storageServiceProvider);
    await storage.saveAccountConfig(config);
    final imap = (imapPassword != null && imapPassword.isNotEmpty)
        ? imapPassword
        : await storage.readImapPassword();
    final smtp = (smtpPassword != null && smtpPassword.isNotEmpty)
        ? smtpPassword
        : await storage.readSmtpPassword();
    if (imap == null || smtp == null) {
      throw StateError('Mot de passe requis');
    }
    await storage.saveCredentials(imapPassword: imap, smtpPassword: smtp);
    state = AsyncData(config);
  }

  Future<void> clear() async {
    final storage = ref.read(storageServiceProvider);
    await storage.clearAccountConfig();
    await storage.clearCredentials();
    state = const AsyncData(null);
  }
}

final accountConfigProvider =
    AsyncNotifierProvider<AccountConfigNotifier, MailAccountConfig?>(
  AccountConfigNotifier.new,
);
