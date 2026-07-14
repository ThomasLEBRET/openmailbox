import 'dart:io';

import 'package:enough_mail/enough_mail.dart' show MailAddress;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/config_provider.dart';
import '../services/smtp_service.dart';
import '../theme.dart';

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

class _Attachment {
  const _Attachment(this.file, this.size);

  final XFile file;
  final int size;

  String get name => file.name;
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  static const _maxAttachmentBytes = 10 * 1024 * 1024; // 10 Mo total

  final _formKey = GlobalKey<FormState>();

  late final _to = TextEditingController(text: widget.initialTo);
  final _cc = TextEditingController();
  final _bcc = TextEditingController();
  late final _subject = TextEditingController(text: widget.initialSubject);
  late final _body = TextEditingController(text: widget.initialBody);

  final List<_Attachment> _attachments = [];
  bool _showCcBcc = false;
  bool _isSending = false;
  String? _error;

  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  int get _attachmentsTotal =>
      _attachments.fold(0, (sum, attachment) => sum + attachment.size);

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

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  Future<void> _pickAttachments() async {
    final files = await openFiles();
    if (files.isEmpty) return;

    var total = _attachmentsTotal;
    final tooBig = <String>[];
    for (final file in files) {
      final size = await file.length();
      if (total + size > _maxAttachmentBytes) {
        tooBig.add(file.name);
        continue;
      }
      total += size;
      _attachments.add(_Attachment(file, size));
    }
    setState(() {
      _error = tooBig.isEmpty
          ? null
          : 'Limite de 10 Mo dépassée — non joint : ${tooBig.join(', ')}';
    });
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final account = ref.read(currentAccountProvider);
    if (account == null) return;
    final config = account.config;

    setState(() {
      _isSending = true;
      _error = null;
    });
    final smtp = SmtpService();
    try {
      final storage = ref.read(storageServiceProvider);
      final password = await storage.readSmtpPassword(account.id);
      if (password == null) {
        throw StateError('Mot de passe SMTP introuvable');
      }

      await smtp.connect(config.smtp, password);
      await smtp.sendMessage(
        from: MailAddress(config.smtp.username, config.smtp.username),
        to: _parseAddresses(_to.text),
        cc: _parseAddresses(_cc.text),
        bcc: _parseAddresses(_bcc.text),
        subject: _subject.text.trim(),
        body: _body.text,
        attachments:
            _attachments.map((a) => File(a.file.path)).toList(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Échec de l\'envoi : $e');
    } finally {
      await smtp.disconnect();
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 700),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
                decoration: BoxDecoration(
                  color: AppColors.sidebarBackground,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.edit_rounded,
                        color: Colors.white70, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Nouveau message',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white70, size: 20),
                      tooltip: 'Fermer',
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              ),
              // Recipients
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  children: [
                    _recipientField(
                      controller: _to,
                      label: 'À',
                      autofocus: widget.initialTo.isEmpty,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Destinataire requis';
                        }
                        final invalid = value
                            .split(',')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .any((s) => !_emailRegex.hasMatch(s));
                        return invalid ? 'Adresse email invalide' : null;
                      },
                      trailing: !_showCcBcc
                          ? TextButton(
                              onPressed: () =>
                                  setState(() => _showCcBcc = true),
                              child: const Text('Cc Cci'),
                            )
                          : null,
                    ),
                    if (_showCcBcc) ...[
                      _recipientField(controller: _cc, label: 'Cc'),
                      _recipientField(controller: _bcc, label: 'Cci'),
                    ],
                    _recipientField(
                      controller: _subject,
                      label: 'Objet',
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                              ? 'Objet requis'
                              : null,
                    ),
                  ],
                ),
              ),
              // Body
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: TextFormField(
                    controller: _body,
                    autofocus: widget.initialTo.isNotEmpty,
                    decoration: const InputDecoration(
                      hintText: 'Écrivez votre message…',
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                    style: const TextStyle(fontSize: 14, height: 1.6),
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                  ),
                ),
              ),
              // Attachments
              if (_attachments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final attachment in _attachments)
                          Chip(
                            avatar: const Icon(Icons.attach_file_rounded,
                                size: 16),
                            label: Text(
                              '${attachment.name} · ${_formatSize(attachment.size)}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            onDeleted: () => setState(
                                () => _attachments.remove(attachment)),
                          ),
                      ],
                    ),
                  ),
                ),
              // Footer
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Joindre des fichiers (10 Mo max)',
                      icon: const Icon(Icons.attach_file_rounded),
                      onPressed: _isSending ? null : _pickAttachments,
                    ),
                    if (_attachments.isNotEmpty)
                      Text(
                        '${_formatSize(_attachmentsTotal)} / 10 Mo',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _error != null
                          ? Text(
                              _error!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: scheme.error,
                                fontSize: 12.5,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    FilledButton.icon(
                      onPressed: _isSending ? null : _send,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentOf(context),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                      ),
                      icon: _isSending
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Envoyer'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Gmail-style inline field: label on the left, underline separator.
  Widget _recipientField({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    Widget? trailing,
    bool autofocus = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: TextFormField(
            controller: controller,
            autofocus: autofocus,
            validator: validator,
            style: const TextStyle(fontSize: 13.5),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.accentOf(context)),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
