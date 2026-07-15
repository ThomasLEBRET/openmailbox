import 'dart:io';

import 'package:enough_mail/enough_mail.dart';

import '../models/config.dart';

/// Thin wrapper around `enough_mail`'s low-level [SmtpClient].
class SmtpService {
  SmtpClient? _client;

  static const _connectTimeout = Duration(seconds: 15);

  Future<void> connect(SmtpConfig config, String password) async {
    final client = SmtpClient(config.host, isLogEnabled: false);
    await client
        .connectToServer(config.host, config.port, isSecure: config.port == 465)
        .timeout(_connectTimeout);
    await client.ehlo().timeout(_connectTimeout);
    if (config.port != 465) {
      await client.startTls().timeout(_connectTimeout);
    }
    if (client.serverInfo.supportsAuth(AuthMechanism.plain)) {
      await client
          .authenticate(config.username, password, AuthMechanism.plain)
          .timeout(_connectTimeout);
    } else {
      await client
          .authenticate(config.username, password, AuthMechanism.login)
          .timeout(_connectTimeout);
    }
    _client = client;
  }

  Future<void> disconnect() async {
    await _client?.quit();
    _client = null;
  }

  Future<void> sendMessage({
    required MailAddress from,
    required List<MailAddress> to,
    List<MailAddress> cc = const [],
    List<MailAddress> bcc = const [],
    required String subject,
    required String body,
    List<File> attachments = const [],
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('SmtpService.connect() must be called first');
    }

    // Defense in depth against header injection: a subject reused from an
    // untrusted incoming email (Re:/Fwd:) could carry CR/LF and smuggle
    // extra headers (e.g. a hidden Bcc). Strip line breaks before it
    // becomes a header.
    subject = subject.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();

    final MimeMessage message;
    if (attachments.isEmpty) {
      // Single-part text/plain. prepareMultipartAlternativeMessage without
      // htmlText renders a multipart envelope with NO body parts, which
      // recipients (e.g. ProtonMail) reject as an invalid message.
      message = MessageBuilder.buildSimpleTextMessage(
        from,
        to,
        body,
        cc: cc,
        bcc: bcc,
        subject: subject,
      );
    } else {
      final builder = MessageBuilder()
        ..from = [from]
        ..to = to
        ..cc = cc
        ..bcc = bcc
        ..subject = subject
        ..addTextPlain(body);
      for (final file in attachments) {
        await builder.addFile(
          file,
          MediaType.guessFromFileName(file.path),
        );
      }
      message = builder.buildMimeMessage();
    }

    await client.sendMessage(message);
  }
}
