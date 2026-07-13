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

  Future<void> save({
    required MailAccountConfig config,
    required String imapPassword,
    required String smtpPassword,
  }) async {
    final storage = ref.read(storageServiceProvider);
    await storage.saveAccountConfig(config);
    await storage.saveCredentials(
      imapPassword: imapPassword,
      smtpPassword: smtpPassword,
    );
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
