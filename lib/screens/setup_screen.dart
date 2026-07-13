import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/config.dart';
import '../providers/config_provider.dart';
import '../providers/folder_provider.dart';
import '../services/imap_service.dart';
import '../services/smtp_service.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _imapHost = TextEditingController();
  final _imapPort = TextEditingController(text: '993');
  final _imapUsername = TextEditingController();
  final _imapPassword = TextEditingController();

  final _smtpHost = TextEditingController();
  final _smtpPort = TextEditingController(text: '587');
  final _smtpUsername = TextEditingController();
  final _smtpPassword = TextEditingController();

  bool _isTesting = false;
  bool _isSaving = false;
  String? _testResult;

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

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final imap = ImapService();
    final smtp = SmtpService();
    try {
      await imap.connect(_imapConfig, _imapPassword.text);
      await smtp.connect(_smtpConfig, _smtpPassword.text);
      setState(() => _testResult = 'Connexion IMAP et SMTP réussie.');
    } on ImapException catch (e) {
      setState(() => _testResult = 'Échec IMAP: $e');
    } on SmtpException catch (e) {
      setState(() => _testResult = 'Échec SMTP: $e');
    } finally {
      await imap.disconnect();
      await smtp.disconnect();
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _saveAndProceed() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await ref.read(accountConfigProvider.notifier).save(
            config: MailAccountConfig(imap: _imapConfig, smtp: _smtpConfig),
            imapPassword: _imapPassword.text,
            smtpPassword: _smtpPassword.text,
          );
      await ref.read(folderListProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration du compte')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('IMAP', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _field(_imapHost, 'IMAP Host', hint: 'imap.gmail.com'),
                  _field(_imapPort, 'IMAP Port', hint: '993', isNumber: true),
                  _field(_imapUsername, 'IMAP Username'),
                  _field(_imapPassword, 'IMAP Password', obscure: true),
                  const SizedBox(height: 24),
                  Text('SMTP', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _field(_smtpHost, 'SMTP Host', hint: 'smtp.gmail.com'),
                  _field(_smtpPort, 'SMTP Port', hint: '587', isNumber: true),
                  _field(_smtpUsername, 'SMTP Username'),
                  _field(_smtpPassword, 'SMTP Password', obscure: true),
                  const SizedBox(height: 24),
                  if (_testResult != null) ...[
                    Text(_testResult!),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton(
                    onPressed: _isTesting ? null : _testConnection,
                    child: _isTesting
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Test Connection'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _isSaving ? null : _saveAndProceed,
                    child: _isSaving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save & Proceed'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool obscure = false,
    bool isNumber = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return 'Requis';
          if (isNumber && int.tryParse(value.trim()) == null) {
            return 'Doit être un nombre';
          }
          return null;
        },
      ),
    );
  }
}
