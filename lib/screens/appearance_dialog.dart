import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/prefs.dart';
import '../providers/prefs_provider.dart';

/// Appearance customization: theme mode, accent color, density.
/// Every change applies instantly and syncs to the other devices.
class AppearanceDialog extends ConsumerWidget {
  const AppearanceDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider).value ?? const AppPrefs();
    final notifier = ref.read(prefsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Apparence',
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
              Text(
                'Synchronisée entre tes appareils via ta boîte email.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _label(context, 'Thème'),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'system',
                      label: Text('Système'),
                      icon: Icon(Icons.brightness_auto_outlined, size: 16)),
                  ButtonSegment(
                      value: 'light',
                      label: Text('Clair'),
                      icon: Icon(Icons.light_mode_outlined, size: 16)),
                  ButtonSegment(
                      value: 'dark',
                      label: Text('Sombre'),
                      icon: Icon(Icons.dark_mode_outlined, size: 16)),
                ],
                selected: {prefs.themeMode},
                onSelectionChanged: (selection) =>
                    notifier.apply(themeMode: selection.first),
              ),
              const SizedBox(height: 20),
              _label(context, 'Couleur d\'accent'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (name, value) in accentChoices)
                    Tooltip(
                      message: name,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => notifier.apply(accentValue: value),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(value),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: prefs.accentValue == value
                                  ? scheme.onSurface
                                  : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: prefs.accentValue == value
                              ? const Icon(Icons.check,
                                  size: 18, color: Colors.white)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _label(context, 'Densité'),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Affichage compact',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'Rangées resserrées, sans ligne d\'aperçu',
                  style: TextStyle(fontSize: 12),
                ),
                value: prefs.compact,
                onChanged: (value) => notifier.apply(compact: value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
