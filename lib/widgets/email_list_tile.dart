import 'package:flutter/material.dart';

import '../models/email.dart';
import '../theme.dart';

class EmailListTile extends StatelessWidget {
  const EmailListTile({
    super.key,
    required this.email,
    required this.selected,
    required this.onTap,
  });

  final Email email;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sender = email.from.isEmpty ? '?' : email.from;
    final initial = sender[0].toUpperCase();
    final unread = !email.isRead;

    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w500,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          formatEmailDate(email.date),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: unread
                                ? AppColors.primary
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
                        if (unread) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (email.preview.trim().isNotEmpty) ...[
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
