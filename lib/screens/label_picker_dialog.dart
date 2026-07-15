import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/email.dart';
import '../models/prefs.dart';
import '../providers/email_provider.dart';
import '../providers/prefs_provider.dart';

/// Assign labels to [email], create new ones, recolor or delete existing
/// definitions. Labels are IMAP keywords: they sync with the server.
class LabelPickerDialog extends ConsumerStatefulWidget {
  const LabelPickerDialog({super.key, required this.email});

  final Email email;

  @override
  ConsumerState<LabelPickerDialog> createState() => _LabelPickerDialogState();
}

class _LabelPickerDialogState extends ConsumerState<LabelPickerDialog> {
  final _nameController = TextEditingController();
  int _newColor = accentChoices.first.$2;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createLabel() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final label =
        LabelDef(slug: labelSlug(name), name: name, colorValue: _newColor);
    await ref.read(prefsProvider.notifier).upsertLabel(label);
    // Apply it to the email right away.
    await ref
        .read(emailListProvider.notifier)
        .toggleLabel(widget.email.uid, label.slug);
    _nameController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labels = ref.watch(prefsProvider).value?.labels ?? const [];
    // Live view of the email (labels change while the dialog is open).
    final email = ref
            .watch(emailListProvider)
            .value
            ?.where((e) => e.uid == widget.email.uid)
            .firstOrNull ??
        widget.email;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Labels',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              if (labels.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Aucun label — créez le premier ci-dessous.',
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final label in labels)
                        _labelRow(context, label,
                            checked: email.labels.contains(label.slug)),
                    ],
                  ),
                ),
              const Divider(height: 24),
              Text(
                'NOUVEAU LABEL',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        hintText: 'Nom du label',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _createLabel(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _createLabel,
                    child: const Text('Ajouter'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final (_, value) in accentChoices)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _newColor = value),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: Color(value),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _newColor == value
                                ? scheme.onSurface
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labelRow(BuildContext context, LabelDef label,
      {required bool checked}) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Checkbox(
          value: checked,
          onChanged: (_) => ref
              .read(emailListProvider.notifier)
              .toggleLabel(widget.email.uid, label.slug),
        ),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Color(label.colorValue),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5)),
        ),
        // Recolor
        PopupMenuButton<int>(
          tooltip: 'Changer la couleur',
          icon: Icon(Icons.palette_outlined,
              size: 17, color: scheme.onSurfaceVariant),
          onSelected: (value) => ref
              .read(prefsProvider.notifier)
              .upsertLabel(LabelDef(
                  slug: label.slug,
                  name: label.name,
                  colorValue: value)),
          itemBuilder: (context) => [
            for (final (name, value) in accentChoices)
              PopupMenuItem(
                value: value,
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                          color: Color(value), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Text(name, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
          ],
        ),
        IconButton(
          tooltip: 'Supprimer le label',
          icon: Icon(Icons.delete_outline,
              size: 17, color: scheme.onSurfaceVariant),
          onPressed: () =>
              ref.read(prefsProvider.notifier).removeLabel(label.slug),
        ),
      ],
    );
  }
}
