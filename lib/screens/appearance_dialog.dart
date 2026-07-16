import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/prefs.dart';
import '../providers/prefs_provider.dart';
import '../services/foreground_mail_service.dart';
import '../services/notification_service.dart';

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
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 640),
        child: SingleChildScrollView(
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
              _label(context, 'Typographie'),
              const SizedBox(height: 8),
              SegmentedButton<String?>(
                segments: [
                  for (final (name, family) in fontChoices)
                    ButtonSegment(value: family, label: Text(name)),
                ],
                selected: {prefs.fontFamily},
                onSelectionChanged: (selection) =>
                    notifier.apply(fontFamily: selection.first),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.text_fields, size: 15),
                  Expanded(
                    child: Slider(
                      value: prefs.fontScale.clamp(0.85, 1.3),
                      min: 0.85,
                      max: 1.3,
                      divisions: 9,
                      label: '${(prefs.fontScale * 100).round()} %',
                      onChanged: (value) =>
                          notifier.apply(fontScale: value),
                    ),
                  ),
                  const Icon(Icons.text_fields, size: 22),
                ],
              ),
              const SizedBox(height: 12),
              _label(context, 'Affichage'),
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Masquer le volet de lecture',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'Liste pleine largeur, les mails s\'ouvrent en plein écran',
                  style: TextStyle(fontSize: 12),
                ),
                value: prefs.hideReader,
                onChanged: (value) => notifier.apply(hideReader: value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bloquer les images distantes',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'Confidentialité : chargement à la demande dans chaque mail',
                  style: TextStyle(fontSize: 12),
                ),
                value: prefs.blockRemoteImages,
                onChanged: (value) =>
                    notifier.apply(blockRemoteImages: value),
              ),
              const SizedBox(height: 12),
              _label(context, 'Délai d\'annulation d\'envoi'),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Aucun')),
                  ButtonSegment(value: 5, label: Text('5 s')),
                  ButtonSegment(value: 10, label: Text('10 s')),
                  ButtonSegment(value: 30, label: Text('30 s')),
                ],
                selected: {prefs.undoSendSeconds},
                onSelectionChanged: (selection) =>
                    notifier.apply(undoSendSeconds: selection.first),
              ),
              const SizedBox(height: 16),
              _label(context, 'Gestes de balayage (mobile)'),
              const SizedBox(height: 8),
              _swipeRow(
                context,
                icon: Icons.swipe_right_alt_rounded,
                title: 'Balayer vers la droite',
                current: prefs.swipeRight,
                onChanged: (a) => notifier.apply(swipeRightAction: a.name),
              ),
              _swipeRow(
                context,
                icon: Icons.swipe_left_alt_rounded,
                title: 'Balayer vers la gauche',
                current: prefs.swipeLeft,
                onChanged: (a) => notifier.apply(swipeLeftAction: a.name),
              ),
              if (Platform.isAndroid) ...[
                const SizedBox(height: 16),
                _label(context, 'Notifications'),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Notifications instantanées',
                      style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    'Connexion maintenue en arrière-plan pour recevoir les '
                    'mails app fermée (notification permanente, un peu plus de '
                    'batterie). Sinon, notifications seulement quand l\'app est '
                    'ouverte.',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: prefs.instantNotifications,
                  onChanged: (value) async {
                    notifier.apply(instantNotifications: value);
                    if (value) {
                      await NotificationService.init();
                      await startMailWatcher();
                    } else {
                      await stopMailWatcher();
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _swipeRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required SwipeAction current,
    required ValueChanged<SwipeAction> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 13.5))),
          DropdownButton<SwipeAction>(
            value: current,
            underline: const SizedBox.shrink(),
            borderRadius: BorderRadius.circular(10),
            items: [
              for (final action in SwipeAction.values)
                DropdownMenuItem(
                  value: action,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(action.icon, size: 16, color: action.color),
                      const SizedBox(width: 8),
                      Text(action.label, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ],
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
