import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/imap_service.dart';
import 'config_provider.dart';

/// Persistent IMAP connection for interactive work (list, open, flags).
final imapServiceProvider = Provider<ImapService>((ref) => ImapService());

/// Second persistent connection for slow background work (folder STATUS
/// storms on servers without LIST-STATUS) so user actions never queue
/// behind it.
final imapBackgroundServiceProvider =
    Provider<ImapService>((ref) => ImapService());

/// Runs [action] on a shared IMAP connection, connecting if needed.
/// On failure the connection is reset and the action retried once —
/// idle sessions are routinely dropped by servers.
Future<T> withImapSession<T>(
  Ref ref,
  Future<T> Function(ImapService imap) action, {
  bool background = false,
}) async {
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

  final imap = ref.read(
      background ? imapBackgroundServiceProvider : imapServiceProvider);
  await imap.ensureConnected(config.imap, password);
  try {
    return await action(imap);
  } catch (_) {
    imap.reset();
    await imap.ensureConnected(config.imap, password);
    return action(imap);
  }
}
