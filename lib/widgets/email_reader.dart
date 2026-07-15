import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/email.dart';
import '../providers/prefs_provider.dart';
import '../theme.dart';

class EmailReader extends StatelessWidget {
  const EmailReader({
    super.key,
    required this.email,
    required this.body,
    required this.bodyIsHtml,
    required this.onReply,
    required this.onForward,
    required this.onDelete,
    required this.onToggleRead,
    this.onLabel,
  });

  final Email email;
  final String? body;
  final bool bodyIsHtml;
  final VoidCallback onReply;
  final VoidCallback onForward;
  final VoidCallback onDelete;
  final VoidCallback onToggleRead;
  final VoidCallback? onLabel;

  static Future<void> _openLink(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sender = email.from.isEmpty ? '?' : email.from;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sticky action toolbar (direction B): compact buttons with their
        // keyboard shortcut, always at the same place.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: Row(
            children: [
              _ToolbarButton(
                icon: Icons.reply_rounded,
                label: 'Répondre',
                shortcut: 'R',
                onPressed: onReply,
              ),
              const SizedBox(width: 6),
              _ToolbarButton(
                icon: Icons.forward_rounded,
                label: 'Transférer',
                shortcut: 'F',
                onPressed: onForward,
              ),
              const SizedBox(width: 6),
              _ToolbarButton(
                icon: email.isRead
                    ? Icons.mark_email_unread_outlined
                    : Icons.mark_email_read_outlined,
                label: email.isRead ? 'Non lu' : 'Lu',
                shortcut: 'U',
                onPressed: onToggleRead,
              ),
              if (onLabel != null) ...[
                const SizedBox(width: 6),
                _ToolbarButton(
                  icon: Icons.label_outline_rounded,
                  label: 'Étiqueter',
                  shortcut: 'L',
                  onPressed: onLabel!,
                ),
              ],
              const Spacer(),
              _ToolbarButton(
                icon: Icons.delete_outline_rounded,
                label: 'Supprimer',
                shortcut: '⌫',
                danger: true,
                onPressed: onDelete,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                email.subject,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.avatarColorFor(sender),
                    child: Text(
                      sender[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          email.fromEmail.isNotEmpty &&
                                  email.fromEmail != sender
                              ? '$sender <${email.fromEmail}>'
                              : sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                        if (email.to.isNotEmpty)
                          Text(
                            'À : ${email.to}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        Text(
                          formatEmailDate(email.date),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
        const Divider(),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    final content = body;
    if (content == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (bodyIsHtml) {
      return _HtmlBodyView(html: content);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SelectableLinkify(
        text: content,
        onOpen: (link) => _openLink(link.url),
        style: const TextStyle(fontSize: 14, height: 1.6),
        linkStyle: TextStyle(
          color: AppColors.accentOf(context),
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

/// Compact toolbar button with its keyboard shortcut displayed.
class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.shortcut,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String shortcut;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger ? scheme.error : scheme.onSurfaceVariant;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(
          color: (danger ? scheme.error : scheme.outlineVariant)
              .withValues(alpha: 0.45),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12.5)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              shortcut,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders HTML emails in a native WebView (WebKit on macOS/iOS) — the
/// only engine that handles real-world table-based email layouts.
/// JavaScript stays disabled; link clicks open the external browser.
/// Remote images are stripped by default (tracking pixels) and load
/// on demand via the banner button.
class _HtmlBodyView extends ConsumerStatefulWidget {
  const _HtmlBodyView({required this.html});

  final String html;

  @override
  ConsumerState<_HtmlBodyView> createState() => _HtmlBodyViewState();
}

class _HtmlBodyViewState extends ConsumerState<_HtmlBodyView> {
  late final WebViewController _controller;
  late bool _showImages;
  late bool _hasRemoteImages;

  // Any remote reference an email could use to phone home: img/src,
  // srcset, CSS url(), <link>, backgrounds… Used only to decide whether
  // to show the "load images" banner; the actual blocking is done by the
  // injected Content-Security-Policy, which the render engine enforces
  // and no regex can be tricked around.
  static final _remoteRef = RegExp(
    r'''(src|srcset|href|background)\s*=\s*['"]?https?://|url\(\s*['"]?https?://''',
    caseSensitive: false,
  );

  @override
  void initState() {
    super.initState();
    _showImages = !(ref.read(prefsProvider).value?.blockRemoteImages ?? true);
    _hasRemoteImages = _remoteRef.hasMatch(widget.html);
    // Note: setBackgroundColor is NOT called — it throws
    // UnimplementedError on macOS and kills the whole widget subtree.
    // The ColoredBox in build() provides the white backdrop instead.
    _controller = WebViewController()
      // Emails are untrusted content: JavaScript MUST stay disabled so a
      // malicious HTML mail can't run scripts (exfiltration, tracking,
      // WebKit exploits). WKWebView enables JS natively by default, so
      // this call is required, not decorative.
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url;
            // User-initiated clicks (web links, mailto) open externally.
            if (url.startsWith('http://') ||
                url.startsWith('https://') ||
                url.startsWith('mailto:')) {
              EmailReader._openLink(url);
              return NavigationDecision.prevent;
            }
            // Only the initial in-memory document load may proceed inside
            // the WebView. Everything else — file://, custom schemes an
            // email might smuggle in — is blocked (local file access).
            if (url.startsWith('about:') || url.startsWith('data:')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadHtmlString(_document(widget.html, blockRemote: !_showImages));
  }

  @override
  void didUpdateWidget(covariant _HtmlBodyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) {
      _showImages =
          !(ref.read(prefsProvider).value?.blockRemoteImages ?? true);
      _hasRemoteImages = _remoteRef.hasMatch(widget.html);
      _controller.loadHtmlString(
          _document(widget.html, blockRemote: !_showImages));
    }
  }

  void _revealImages() {
    setState(() => _showImages = true);
    _controller.loadHtmlString(_document(widget.html, blockRemote: false));
  }

  /// A CSP that lets the mail render but blocks it from reaching the
  /// network: no scripts at all, images and fonts only from inline data:
  /// (and cid: parts), styles inline only. When the user reveals images,
  /// remote img/style/font sources are allowed but scripts stay banned.
  static String _csp({required bool blockRemote}) {
    final content = blockRemote
        ? "default-src 'none'; img-src data: cid:; "
            "style-src 'unsafe-inline'; font-src data:;"
        : "default-src 'none'; img-src data: cid: https: http:; "
            "style-src 'unsafe-inline' https: http:; "
            "font-src data: https: http:;";
    return '<meta http-equiv="Content-Security-Policy" content="$content">';
  }

  /// Wraps fragments in a readable shell and always injects the CSP
  /// (into the existing head for full documents).
  static String _document(String html, {required bool blockRemote}) {
    final csp = _csp(blockRemote: blockRemote);
    if (html.toLowerCase().contains('<head')) {
      return html.replaceFirstMapped(
        RegExp('<head[^>]*>', caseSensitive: false),
        (m) => '${m[0]}$csp',
      );
    }
    if (html.toLowerCase().contains('<html')) {
      return html.replaceFirstMapped(
        RegExp('<html[^>]*>', caseSensitive: false),
        (m) => '${m[0]}<head>$csp</head>',
      );
    }
    return '''
<!DOCTYPE html>
<html>
<head>
$csp
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body {
    margin: 16px;
    font-family: -apple-system, Helvetica, Arial, sans-serif;
    font-size: 14px;
    line-height: 1.6;
    color: #222;
    background: #fff;
    word-wrap: break-word;
  }
  img { max-width: 100%; height: auto; }
</style>
</head>
<body>$html</body>
</html>''';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (_hasRemoteImages && !_showImages)
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.image_not_supported_outlined,
                    size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Images distantes bloquées (confidentialité)',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
                TextButton(
                  onPressed: _revealImages,
                  child: const Text('Afficher les images',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        Expanded(
          child: ColoredBox(
            color: Colors.white,
            child: WebViewWidget(controller: _controller),
          ),
        ),
      ],
    );
  }
}
