import 'package:flutter/material.dart';

import '../models/email.dart';
import '../theme.dart';

class EmailListTile extends StatefulWidget {
  const EmailListTile({
    super.key,
    required this.email,
    required this.selected,
    required this.onTap,
    required this.onReply,
    required this.onForward,
    required this.onToggleRead,
    required this.onDelete,
  });

  final Email email;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onReply;
  final VoidCallback onForward;
  final VoidCallback onToggleRead;
  final VoidCallback onDelete;

  @override
  State<EmailListTile> createState() => _EmailListTileState();
}

class _EmailListTileState extends State<EmailListTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final email = widget.email;
    final sender = email.from.isEmpty ? '?' : email.from;
    final initial = sender[0].toUpperCase();
    final unread = !email.isRead;
    final compact = AppColors.compactOf(context);

    // Floating card (direction A): clearly detached from the background —
    // border + shadow + gap — with a purple left edge for unread and an
    // accent outline when selected.
    final accent = AppColors.accentOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 3 : 5),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: widget.selected
              ? scheme.primaryContainer.withValues(alpha: 0.35)
              : _hovered
              ? scheme.surfaceContainerHigh
              : scheme.surfaceContainer,
          elevation: _hovered || widget.selected ? 4 : 1.5,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: widget.selected
                  ? accent
                  : scheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border(
                  left: BorderSide(
                    color: unread ? accent : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              padding: EdgeInsets.symmetric(
                  horizontal: 13, vertical: compact ? 6 : 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.avatarColorFor(sender),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                sender,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: unread
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_hovered)
                              _QuickActions(
                                isRead: email.isRead,
                                onReply: widget.onReply,
                                onForward: widget.onForward,
                                onToggleRead: widget.onToggleRead,
                                onDelete: widget.onDelete,
                              )
                            else
                              Text(
                                formatEmailDate(email.date),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: unread
                                      ? AppColors.accentOf(context)
                                      : scheme.onSurfaceVariant,
                                  fontWeight: unread
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                email.subject,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: unread
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ),
                            if (unread && !_hovered) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: AppColors.accentOf(context),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (!compact && email.preview.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            email.preview
                                .replaceAll(RegExp(r'\s+'), ' ')
                                .trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact hover toolbar: mark read/unread, reply, forward, delete.
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.isRead,
    required this.onReply,
    required this.onForward,
    required this.onToggleRead,
    required this.onDelete,
  });

  final bool isRead;
  final VoidCallback onReply;
  final VoidCallback onForward;
  final VoidCallback onToggleRead;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget action(
      IconData icon,
      String tooltip,
      VoidCallback onPressed, {
      Color? color,
    }) {
      return Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              icon,
              size: 17,
              color: color ?? scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        action(
          isRead
              ? Icons.mark_email_unread_outlined
              : Icons.mark_email_read_outlined,
          isRead ? 'Marquer non lu' : 'Marquer lu',
          onToggleRead,
        ),
        action(Icons.reply_rounded, 'Répondre', onReply),
        action(Icons.forward_rounded, 'Transférer', onForward),
        action(
          Icons.delete_outline_rounded,
          'Supprimer',
          onDelete,
          color: scheme.error,
        ),
      ],
    );
  }
}
