import 'package:enough_mail/enough_mail.dart' show MailAddress;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/config_provider.dart';
import '../services/smtp_service.dart';

/// Modal for composing a new email, or a reply/forward when [initialTo],
/// [initialSubject] or [initialBody] are provided.
class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({
    super.key,
    this.initialTo = '',
    this.initialSubject = '',
    this.initialBody = '',
  });

  final String initialTo;
  final String initialSubject;
  final String initialBody;

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _to = TextEditingController(text: widget.initialTo);
  final _cc = TextEditingController();
  final _bcc = TextEditingController();
  late final _subject = TextEditingController(text: widget.initialSubject);
  late final _body = TextEditingController(text: widget.initialBody);

  bool _isSending = false;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    for (final controller in [_to, _cc, _bcc, _subject, _body]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<MailAddress> _parseAddresses(String raw) {
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((email) => MailAddress(email, email))
        .toList();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final config = ref.read(accountConfigProvider).value;
    if (config == null) return;

    setState(() => _isSending = true);
    final smtp = SmtpService();
    try {
      final storage = ref.read(storageServiceProvider);
      final password = await storage.readSmtpPassword();
      if (password == null) return;

      await smtp.connect(config.smtp, password);
      await smtp.sendMessage(
        from: MailAddress(config.smtp.username, config.smtp.username),
        to: _parseAddresses(_to.text),
        cc: _parseAddresses(_cc.text),
        bcc: _parseAddresses(_bcc.text),
        subject: _subject.text.trim(),
        body: _body.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      await smtp.disconnect();
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Nouveau message',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
                TextFormField(
                  controller: _to,
                  decoration: const InputDecoration(labelText: 'To'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Requis';
                    final invalid = value
                        .split(',')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .any((s) => !_emailRegex.hasMatch(s));
                    return invalid ? 'Adresse email invalide' : null;
                  },
                ),
                TextFormField(
                  controller: _cc,
                  decoration: const InputDecoration(labelText: 'Cc'),
                ),
                TextFormField(
                  controller: _bcc,
                  decoration: const InputDecoration(labelText: 'Bcc'),
                ),
                TextFormField(
                  controller: _subject,
                  decoration: const InputDecoration(labelText: 'Subject'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TextFormField(
                    controller: _body,
                    decoration: const InputDecoration(
                      labelText: 'Body',
                      alignLabelWithHint: true,
                    ),
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton.icon(
                      onPressed: _isSending ? null : _send,
                      icon: _isSending
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: const Text('Send'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
