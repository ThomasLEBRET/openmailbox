import 'package:flutter/material.dart';

import '../models/email.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(email.subject, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('De: ${email.from}'),
              Text('Date: ${email.date}'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: onReply,
                    icon: const Icon(Icons.reply),
                    label: const Text('Répondre'),
                  ),
                  TextButton.icon(
                    onPressed: onForward,
                    icon: const Icon(Icons.forward),
                    label: const Text('Transférer'),
                  ),
                  TextButton.icon(
                    onPressed: onToggleRead,
                    icon: const Icon(Icons.mark_email_read_outlined),
                    label: Text(email.isRead ? 'Non lu' : 'Lu'),
                  ),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Supprimer'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: body == null
                ? const Center(child: CircularProgressIndicator())
                : Text(body!),
          ),
        ),
      ],
    );
  }
}
