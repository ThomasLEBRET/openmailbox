import 'package:flutter/material.dart';

import '../models/email.dart';

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
    final initials = email.from.isNotEmpty ? email.from[0].toUpperCase() : '?';

    return ListTile(
      selected: selected,
      leading: CircleAvatar(child: Text(initials)),
      title: Text(
        email.subject,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: email.isRead ? FontWeight.normal : FontWeight.bold,
        ),
      ),
      subtitle: Text(
        '${email.from} — ${email.preview}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${email.date.day}/${email.date.month}/${email.date.year}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!email.isRead)
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}
