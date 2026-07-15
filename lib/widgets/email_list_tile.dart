import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/email.dart';
import '../models/prefs.dart';
import '../providers/prefs_provider.dart';
import '../theme.dart';

class EmailListTile extends ConsumerStatefulWidget {
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
    this.onMove,
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

  /// Opens the folder picker (drag on desktop, swipe on mobile).
  final VoidCallback? onMove;

  /// True when at least one email is checked: checkboxes stay visible
  /// and tapping toggles instead of opening.
  final bool selectionMode;
  final bool checked;
  final ValueChanged<bool>? onCheckChanged;

  @override
  ConsumerState<EmailListTile> createState() => _EmailListTileState();
}

class _EmailListTileState extends ConsumerState<EmailListTile> {
  bool _hovered = false;

  VoidCallback? _actionFor(SwipeAction action) => switch (action) {
        SwipeAction.read => widget.onToggleRead,
        SwipeAction.flag => widget.onToggleFlag,
        SwipeAction.delete => widget.onDelete,
        SwipeAction.move => widget.onMove,
        SwipeAction.none => null,
      };

  Widget _swipeBackground(SwipeAction action, {required bool alignStart}) {
    return Container(
      color: action.color.withValues(alpha: 0.9),
      alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(action.icon, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.email;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final card = _card(context);

    Widget wrapped;
    if (isMobile && !widget.selectionMode) {
      // Touch: swipe left/right for the two configured actions. No drag —
      // long-press-to-move makes no sense on a phone.
      final prefs = ref.watch(prefsProvider).value ?? const AppPrefs();
      final right = prefs.swipeRight; // swipe →  (startToEnd)
      final left = prefs.swipeLeft; //  swipe ←  (endToStart)
      final rightCb = _actionFor(right);
      final leftCb = _actionFor(left);

      final direction = rightCb != null && leftCb != null
          ? DismissDirection.horizontal
          : rightCb != null
              ? DismissDirection.startToEnd
              : leftCb != null
                  ? DismissDirection.endToStart
                  : DismissDirection.none;

      wrapped = Dismissible(
        key: ValueKey('${email.folder}-${email.uid}'),
        direction: direction,
        background: rightCb != null
            ? _swipeBackground(right, alignStart: true)
            : null,
        secondaryBackground:
            leftCb != null ? _swipeBackground(left, alignStart: false) : null,
        // Always return false: the action itself removes the row from the
        // list when needed (delete/move) via the provider, so Dismissible
        // never has to detach it — avoids "dismissed widget still in tree".
        confirmDismiss: (dir) async {
          (dir == DismissDirection.startToEnd ? rightCb : leftCb)?.call();
          return false;
        },
        child: card,
      );
    } else if (!isMobile) {
      // Desktop: drag onto a sidebar folder to move.
      wrapped = Draggable<Email>(
        data: email,
        feedback: _dragFeedback(context),
        dragAnchorStrategy: pointerDragAnchorStrategy,
        childWhenDragging: Opacity(opacity: 0.35, child: _placeholder(context)),
        child: card,
      );
    } else {
      wrapped = card;
    }

    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: AppColors.compactOf(context) ? 3 : 5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: wrapped,
      ),
    );
  }

  Widget _card(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final email = widget.email;
    final sender = email.from.isEmpty ? '?' : email.from;
    final initial = sender[0].toUpperCase();
    final unread = !email.isRead;
    final compact = AppColors.compactOf(context);
    final accent = AppColors.accentOf(context);

    return MouseRegion(
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
            padding:
                EdgeInsets.symmetric(horizontal: 13, vertical: compact ? 6 : 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.selectionMode ||
                    (_hovered && widget.onCheckChanged != null))
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
                                fontWeight:
                                    unread ? FontWeight.w700 : FontWeight.w500,
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
                                    ? accent
                                    : scheme.onSurfaceVariant,
                                fontWeight:
                                    unread ? FontWeight.w600 : FontWeight.w400,
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
                                fontWeight:
                                    unread ? FontWeight.w600 : FontWeight.w400,
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
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (!compact && email.preview.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          email.preview.replaceAll(RegExp(r'\s+'), ' ').trim(),
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
    );
  }

  Widget _dragFeedback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = AppColors.accentOf(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drive_file_move_outlined, size: 16, color: accent),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                widget.email.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: SizedBox(
        height: 60,
        child: Center(
          child: Text(
            widget.email.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
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
            child: Icon(icon, size: 17, color: color ?? scheme.onSurfaceVariant),
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

    final dark = Theme.of(context).brightness == Brightness.dark;
    return Wrap(
      spacing: 6,
      children: [
        for (final label in matched)
          Builder(builder: (context) {
            final base = Color(label.colorValue);
            final text = Color.lerp(
                base, dark ? Colors.white : Colors.black, dark ? 0.45 : 0.4)!;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: base.withValues(alpha: dark ? 0.28 : 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: base.withValues(alpha: 0.65)),
              ),
              child: Text(
                label.name,
                style: TextStyle(
                  fontSize: 10.5,
                  color: text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }),
      ],
    );
  }
}
