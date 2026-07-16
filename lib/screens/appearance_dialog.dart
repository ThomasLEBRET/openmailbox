import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/prefs.dart';
import '../providers/prefs_provider.dart';
import '../services/foreground_mail_service.dart';
import '../services/notification_service.dart';

/// App preferences, grouped into clear sections: appearance, notifications,
/// swipe gestures, trash, sending, and an "about" block with the version.
/// Full-screen page on phones, centered dialog on desktop. Every change
/// applies instantly and syncs to the other devices.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final content = _SettingsContent(scrollable: true);

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(title: const Text('Paramètres')),
        body: SafeArea(child: content),
      );
    }
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Paramètres',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(child: content),
          ],
        ),
      ),
    );
  }
}

/// Backwards-compatible alias — some call sites still say "AppearanceDialog".
class AppearanceDialog extends StatelessWidget {
  const AppearanceDialog({super.key});
  @override
  Widget build(BuildContext context) => const SettingsScreen();
}

class _SettingsContent extends ConsumerWidget {
  const _SettingsContent({required this.scrollable});

  final bool scrollable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider).value ?? const AppPrefs();
    final notifier = ref.read(prefsProvider.notifier);

    final sections = <Widget>[
      _Section(
        title: 'Apparence',
        subtitle: 'Synchronisée entre tes appareils via ta boîte email.',
        children: [
          _label(context, 'Thème'),
          const SizedBox(height: 8),
          Row(
            children: [
              _choice(context,
                  icon: Icons.brightness_auto_outlined,
                  label: 'Système',
                  selected: prefs.themeMode == 'system',
                  onTap: () => notifier.apply(themeMode: 'system')),
              const SizedBox(width: 8),
              _choice(context,
                  icon: Icons.light_mode_outlined,
                  label: 'Clair',
                  selected: prefs.themeMode == 'light',
                  onTap: () => notifier.apply(themeMode: 'light')),
              const SizedBox(width: 8),
              _choice(context,
                  icon: Icons.dark_mode_outlined,
                  label: 'Sombre',
                  selected: prefs.themeMode == 'dark',
                  onTap: () => notifier.apply(themeMode: 'dark')),
            ],
          ),
          const SizedBox(height: 18),
          _label(context, 'Couleur d\'accent'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (name, value) in accentChoices)
                _AccentSwatch(
                  name: name,
                  value: value,
                  selected: prefs.accentValue == value,
                  onTap: () => notifier.apply(accentValue: value),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _label(context, 'Typographie'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (name, family) in fontChoices) ...[
                _choice(context,
                    label: name,
                    selected: prefs.fontFamily == family,
                    onTap: () => notifier.apply(fontFamily: family)),
                if (name != fontChoices.last.$1) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 6),
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
                  onChanged: (value) => notifier.apply(fontScale: value),
                ),
              ),
              const Icon(Icons.text_fields, size: 22),
            ],
          ),
          const Divider(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Affichage compact',
                style: TextStyle(fontSize: 14)),
            subtitle: const Text('Rangées resserrées, sans ligne d\'aperçu',
                style: TextStyle(fontSize: 12)),
            value: prefs.compact,
            onChanged: (value) => notifier.apply(compact: value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Masquer le volet de lecture',
                style: TextStyle(fontSize: 14)),
            subtitle: const Text(
                'Liste pleine largeur, les mails s\'ouvrent en plein écran',
                style: TextStyle(fontSize: 12)),
            value: prefs.hideReader,
            onChanged: (value) => notifier.apply(hideReader: value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Bloquer les images distantes',
                style: TextStyle(fontSize: 14)),
            subtitle: const Text(
                'Confidentialité : chargement à la demande dans chaque mail',
                style: TextStyle(fontSize: 12)),
            value: prefs.blockRemoteImages,
            onChanged: (value) => notifier.apply(blockRemoteImages: value),
          ),
        ],
      ),
      if (Platform.isAndroid)
        _Section(
          title: 'Notifications',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Notifications en arrière-plan',
                  style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                  'Vérifie tous tes dossiers app fermée (~1 min), notification '
                  'permanente, un peu plus de batterie. Sinon, notifications '
                  'seulement quand l\'app est ouverte.',
                  style: TextStyle(fontSize: 12)),
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
        ),
      _Section(
        title: 'Gestes de balayage',
        subtitle: 'Sur mobile, action déclenchée en faisant glisser un email.',
        children: [
          _swipeRow(context,
              icon: Icons.swipe_right_alt_rounded,
              title: 'Vers la droite',
              current: prefs.swipeRight,
              onChanged: (a) => notifier.apply(swipeRightAction: a.name)),
          _swipeRow(context,
              icon: Icons.swipe_left_alt_rounded,
              title: 'Vers la gauche',
              current: prefs.swipeLeft,
              onChanged: (a) => notifier.apply(swipeLeftAction: a.name)),
        ],
      ),
      _Section(
        title: 'Corbeille',
        children: [
          _label(context, 'Vidage automatique'),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Jamais')),
              ButtonSegment(value: 7, label: Text('7 j')),
              ButtonSegment(value: 30, label: Text('30 j')),
              ButtonSegment(value: 90, label: Text('90 j')),
            ],
            selected: {prefs.autoEmptyTrashDays},
            onSelectionChanged: (s) =>
                notifier.apply(autoEmptyTrashDays: s.first),
          ),
        ],
      ),
      _Section(
        title: 'Envoi',
        children: [
          _label(context, 'Délai d\'annulation'),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Aucun')),
              ButtonSegment(value: 5, label: Text('5 s')),
              ButtonSegment(value: 10, label: Text('10 s')),
              ButtonSegment(value: 30, label: Text('30 s')),
            ],
            selected: {prefs.undoSendSeconds},
            onSelectionChanged: (s) =>
                notifier.apply(undoSendSeconds: s.first),
          ),
        ],
      ),
      const _AboutSection(),
    ];

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final section in sections) ...[
          section,
          const SizedBox(height: 12),
        ],
      ],
    );

    final padded = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: column,
    );

    return scrollable ? SingleChildScrollView(child: padded) : padded;
  }

  Widget _choice(BuildContext context,
      {IconData? icon,
      required String label,
      required bool selected,
      required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.12)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 20,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(height: 4),
              ],
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: selected ? scheme.primary : scheme.onSurface,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
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

/// A titled card grouping related settings.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!,
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.name,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final int value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: name,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Color(value),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, size: 20, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

/// App identity + version at the bottom of the settings.
class _AboutSection extends StatefulWidget {
  const _AboutSection();

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  String _version = '…';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = 'v${info.version} (${info.buildNumber})');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Section(
      title: 'À propos',
      children: [
        Row(
          children: [
            const Icon(Icons.mail_rounded, color: Color(0xFF6D4AFF), size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('OpenMailbox',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            SelectableText(
              _version,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}
