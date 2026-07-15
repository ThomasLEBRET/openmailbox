import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/email.dart';
import '../providers/prefs_provider.dart';
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
    required this.onToggleFlag,
    this.onLabel,
    this.selectionMode = false,
    this.checked = false,
    this.onCheckChanged,
  });

  final Email email;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onReply;
  final VoidCallback onForward;
  final VoidCallback onToggleRead;
  final VoidCallback onDelete;
  final VoidCallback onToggleFlag;
  final VoidCallback? onLabel;

  /// True when at least one email is checked: checkboxes stay visible
  /// and tapping toggles instead of opening.
  final bool selectionMode;
  final bool checked;
  final ValueChanged<bool>? onCheckChanged;

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

    final dragFeedback = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 12),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drive_file_move_outlined, size: 16, color: accent),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                email.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 3 : 5),
      child: Draggable<Email>(
        data: email,
        feedback: dragFeedback,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        childWhenDragging: Opacity(opacity: 0.35, child: _card(context)),
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
            onTap: widget.selectionMode
                ? () => widget.onCheckChanged?.call(!widget.checked)
                : widget.onTap,
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
                  if (widget.selectionMode || (_hovered && widget.onCheckChanged != null))
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: Checkbox(
                        value: widget.checked,
                        onChanged: (value) =>
                            widget.onCheckChanged?.call(value ?? false),
                      ),
                    )
                  else
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
                            if (email.isFlagged && !_hovered) ...[
                              const Icon(Icons.star_rounded,
                                  size: 15, color: Color(0xFFF2B01E)),
                              const SizedBox(width: 4),
                            ],
                            const SizedBox(width: 8),
                            if (_hovered)
                              _QuickActions(
                                isRead: email.isRead,
                                isFlagged: email.isFlagged,
                                onReply: widget.onReply,
                                onForward: widget.onForward,
                                onToggleRead: widget.onToggleRead,
                                onDelete: widget.onDelete,
                                onToggleFlag: widget.onToggleFlag,
                                onLabel: widget.onLabel,
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
                        if (email.labels.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _LabelChips(slugs: email.labels),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  /// Static snapshot of the card used as childWhenDragging.
  Widget _card(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: SizedBox(
        height: 60,
        child: Center(
          child: Text(
            widget.email.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12.5, color: scheme.onSurfaceVariant),
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
    required this.isFlagged,
    required this.onReply,
    required this.onForward,
    required this.onToggleRead,
    required this.onDelete,
    required this.onToggleFlag,
    this.onLabel,
  });

  final bool isRead;
  final bool isFlagged;
  final VoidCallback onReply;
  final VoidCallback onForward;
  final VoidCallback onToggleRead;
  final VoidCallback onDelete;
  final VoidCallback onToggleFlag;
  final VoidCallback? onLabel;

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
          isFlagged ? Icons.star_rounded : Icons.star_outline_rounded,
          isFlagged ? 'Retirer l\'étoile' : 'Ajouter une étoile',
          onToggleFlag,
          color: isFlagged ? const Color(0xFFF2B01E) : null,
        ),
        action(
          isRead
              ? Icons.mark_email_unread_outlined
              : Icons.mark_email_read_outlined,
          isRead ? 'Marquer non lu' : 'Marquer lu',
          onToggleRead,
        ),
        if (onLabel != null)
          action(Icons.label_outline_rounded, 'Étiqueter', onLabel!),
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


/// Small colored chips resolving label slugs against the synced defs.
class _LabelChips extends ConsumerWidget {
  const _LabelChips({required this.slugs});

  final List<String> slugs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defs = ref.watch(prefsProvider).value?.labels ?? const [];
    final matched = [
      for (final slug in slugs)
        defs.where((d) => d.slug == slug).firstOrNull,
    ].nonNulls.take(3).toList();
    if (matched.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      children: [
        for (final label in matched)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: Color(label.colorValue).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Color(label.colorValue).withValues(alpha: 0.6),
              ),
            ),
            child: Text(
              label.name,
              style: TextStyle(
                fontSize: 10.5,
                color: Color(label.colorValue),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
