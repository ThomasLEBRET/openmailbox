import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/config.dart';
import '../providers/config_provider.dart';
import '../services/imap_service.dart';
import '../services/smtp_service.dart';
import '../theme.dart';

/// Account configuration screen with three modes:
/// - first run (no account yet): full-page, saves and enters the app
/// - add account ([isAddingAccount]): pushed, saves a NEW account
/// - edit ([initialConfig] set): prefilled, blank password keeps the
///   stored one, can delete the account
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({
    super.key,
    this.initialConfig,
    this.isAddingAccount = false,
  });

  final MailAccountConfig? initialConfig;
  final bool isAddingAccount;

  bool get isEditing => initialConfig != null;

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _imapHost =
      TextEditingController(text: widget.initialConfig?.imap.host ?? '');
  late final _imapPort = TextEditingController(
      text: widget.initialConfig?.imap.port.toString() ?? '993');
  late final _imapUsername =
      TextEditingController(text: widget.initialConfig?.imap.username ?? '');
  final _imapPassword = TextEditingController();

  late final _smtpHost =
      TextEditingController(text: widget.initialConfig?.smtp.host ?? '');
  late final _smtpPort = TextEditingController(
      text: widget.initialConfig?.smtp.port.toString() ?? '587');
  late final _smtpUsername =
      TextEditingController(text: widget.initialConfig?.smtp.username ?? '');
  final _smtpPassword = TextEditingController();

  late final _signature = TextEditingController(
      text: widget.isEditing
          ? (ref.read(currentAccountProvider)?.signature ?? '')
          : '');

  bool _isTesting = false;
  bool _isSaving = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void dispose() {
    for (final controller in [
      _imapHost,
      _imapPort,
      _imapUsername,
      _imapPassword,
      _smtpHost,
      _smtpPort,
      _smtpUsername,
      _smtpPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  ImapConfig get _imapConfig => ImapConfig(
        host: _imapHost.text.trim(),
        port: int.parse(_imapPort.text.trim()),
        username: _imapUsername.text.trim(),
      );

  SmtpConfig get _smtpConfig => SmtpConfig(
        host: _smtpHost.text.trim(),
        port: int.parse(_smtpPort.text.trim()),
        username: _smtpUsername.text.trim(),
      );

  /// In edit mode an empty password field means "keep the stored one",
  /// so tests fall back to the stored password too.
  Future<String> _effectivePassword(
    String fieldValue,
    Future<String?> Function() readStored,
  ) async {
    if (fieldValue.isNotEmpty) return fieldValue;
    final stored = await readStored();
    if (stored == null) throw StateError('Mot de passe requis');
    return stored;
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = true;
      _statusMessage = null;
    });

    final storage = ref.read(storageServiceProvider);
    final currentId = ref.read(currentAccountProvider)?.id;
    final imap = ImapService();
    final smtp = SmtpService();
    try {
      final imapPassword = await _effectivePassword(
          _imapPassword.text,
          () async => currentId == null
              ? null
              : storage.readImapPassword(currentId));
      final smtpPassword = await _effectivePassword(
          _smtpPassword.text,
          () async => currentId == null
              ? null
              : storage.readSmtpPassword(currentId));
      await imap.ensureConnected(_imapConfig, imapPassword);
      await smtp.connect(_smtpConfig, smtpPassword);
      setState(() {
        _statusMessage = 'Connexion IMAP et SMTP réussie.';
        _statusIsError = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Échec du test : $e';
        _statusIsError = true;
      });
    } finally {
      await imap.disconnect();
      await smtp.disconnect();
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });
    try {
      final config = MailAccountConfig(imap: _imapConfig, smtp: _smtpConfig);
      final accounts = ref.read(accountsProvider.notifier);
      if (widget.isEditing) {
        await accounts.updateCurrent(
          config: config,
          imapPassword: _imapPassword.text,
          smtpPassword: _smtpPassword.text,
          signature: _signature.text,
        );
      } else {
        await accounts.addAccount(
          config: config,
          imapPassword: _imapPassword.text,
          smtpPassword: _smtpPassword.text,
        );
      }
      if ((widget.isEditing || widget.isAddingAccount) && mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Échec de la sauvegarde : $e';
          _statusIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce compte ?'),
        content: const Text(
            'Les identifiants et les données locales de ce compte seront '
            'effacés. Les emails restent sur le serveur.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(accountsProvider.notifier).removeCurrent();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: widget.isEditing
          ? AppBar(title: const Text('Paramètres du compte'))
          : widget.isAddingAccount
              ? AppBar(title: const Text('Ajouter un compte'))
              : null,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!widget.isEditing) ...[
                        Icon(Icons.mail_outline_rounded,
                            size: 48, color: AppColors.primary),
                        const SizedBox(height: 12),
                        Text(
                          'OpenMailbox',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Connectez votre boîte email via IMAP/SMTP',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 28),
                      ],
                      _sectionLabel(context, 'Réception (IMAP)'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _field(_imapHost, 'Serveur',
                                hint: 'imap.exemple.com'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child:
                                _field(_imapPort, 'Port', isNumber: true),
                          ),
                        ],
                      ),
                      _field(_imapUsername, 'Adresse email'),
                      _field(
                        _imapPassword,
                        'Mot de passe',
                        obscure: true,
                        optional: widget.isEditing,
                        helper: widget.isEditing
                            ? 'Laisser vide pour conserver l\'actuel'
                            : null,
                      ),
                      const SizedBox(height: 20),
                      _sectionLabel(context, 'Envoi (SMTP)'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _field(_smtpHost, 'Serveur',
                                hint: 'smtp.exemple.com'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child:
                                _field(_smtpPort, 'Port', isNumber: true),
                          ),
                        ],
                      ),
                      _field(_smtpUsername, 'Adresse email'),
                      _field(
                        _smtpPassword,
                        'Mot de passe',
                        obscure: true,
                        optional: widget.isEditing,
                        helper: widget.isEditing
                            ? 'Laisser vide pour conserver l\'actuel'
                            : null,
                      ),
                      if (widget.isEditing) ...[
                        const SizedBox(height: 20),
                        _sectionLabel(context, 'Signature'),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _signature,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText:
                                'Ajoutée à la fin de vos messages (optionnel)',
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (_statusMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _statusIsError
                                ? scheme.errorContainer
                                : scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _statusMessage!,
                            style: TextStyle(
                              color: _statusIsError
                                  ? scheme.onErrorContainer
                                  : scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      OutlinedButton(
                        onPressed:
                            _isTesting || _isSaving ? null : _testConnection,
                        child: _isTesting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Tester la connexion'),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _isTesting || _isSaving ? null : _save,
                        child: _isSaving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(widget.isEditing
                                ? 'Enregistrer'
                                : widget.isAddingAccount
                                    ? 'Ajouter le compte'
                                    : 'Se connecter'),
                      ),
                      if (widget.isEditing) ...[
                        const SizedBox(height: 20),
                        TextButton.icon(
                          onPressed: _isSaving ? null : _deleteAccount,
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.error,
                          ),
                          icon: const Icon(Icons.delete_forever_outlined,
                              size: 18),
                          label: const Text('Supprimer ce compte'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    String? helper,
    bool obscure = false,
    bool isNumber = false,
    bool optional = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
        ),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) return optional ? null : 'Requis';
          if (isNumber && int.tryParse(text) == null) {
            return 'Doit être un nombre';
          }
          return null;
        },
      ),
    );
  }
}
