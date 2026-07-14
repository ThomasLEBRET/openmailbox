import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/imap_service.dart';
import 'config_provider.dart';

/// Single persistent IMAP connection for the whole app.
final imapServiceProvider = Provider<ImapService>((ref) => ImapService());

/// Runs [action] on the shared IMAP connection, connecting if needed.
/// On failure the connection is reset and the action retried once —
/// idle sessions are routinely dropped by servers.
Future<T> withImapSession<T>(
  Ref ref,
  Future<T> Function(ImapService imap) action,
) async {
  final config = ref.read(accountConfigProvider).value;
  if (config == null) {
    throw StateError('Aucun compte configuré');
  }
  final storage = ref.read(storageServiceProvider);
  final password = await storage.readImapPassword();
  if (password == null) {
    throw StateError(
      'Mot de passe IMAP introuvable dans le trousseau (Keychain). '
      'Reconfigure le compte depuis les réglages.',
    );
  }

  final imap = ref.read(imapServiceProvider);
  await imap.ensureConnected(config.imap, password);
  try {
    return await action(imap);
  } catch (_) {
    imap.reset();
    await imap.ensureConnected(config.imap, password);
    return action(imap);
  }
}
