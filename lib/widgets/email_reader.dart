import 'package:flutter/material.dart';

import '../models/email.dart';
import '../theme.dart';

class EmailReader extends StatelessWidget {
  const EmailReader({
    super.key,
    required this.email,
    required this.body,
    required this.onReply,
    required this.onForward,
    required this.onDelete,
    required this.onToggleRead,
  });

  final Email email;
  final String? body;
  final VoidCallback onReply;
  final VoidCallback onForward;
  final VoidCallback onDelete;
  final VoidCallback onToggleRead;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sender = email.from.isEmpty ? '?' : email.from;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
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
              const SizedBox(height: 16),
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
                          sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
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
                  IconButton(
                    tooltip: 'Répondre',
                    icon: const Icon(Icons.reply_rounded, size: 20),
                    onPressed: onReply,
                  ),
                  IconButton(
                    tooltip: 'Transférer',
                    icon: const Icon(Icons.forward_rounded, size: 20),
                    onPressed: onForward,
                  ),
                  IconButton(
                    tooltip:
                        email.isRead ? 'Marquer non lu' : 'Marquer lu',
                    icon: Icon(
                      email.isRead
                          ? Icons.mark_email_unread_outlined
                          : Icons.mark_email_read_outlined,
                      size: 20,
                    ),
                    onPressed: onToggleRead,
                  ),
                  IconButton(
                    tooltip: 'Supprimer',
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 20, color: scheme.error),
                    onPressed: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: body == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: SelectableText(
                    body!,
                    style: const TextStyle(fontSize: 14, height: 1.6),
                  ),
                ),
        ),
      ],
    );
  }
}
