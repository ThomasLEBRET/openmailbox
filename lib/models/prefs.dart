import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'prefs.freezed.dart';
part 'prefs.g.dart';

/// A user-defined label, synced as an IMAP keyword (`om_slug`).
@freezed
abstract class LabelDef with _$LabelDef {
  const factory LabelDef({
    required String slug,
    required String name,
    required int colorValue,
  }) = _LabelDef;

  factory LabelDef.fromJson(Map<String, dynamic> json) =>
      _$LabelDefFromJson(json);
}

/// Turns a label name into its IMAP keyword slug.
String labelSlug(String name) {
  final cleaned = name
      .toLowerCase()
      .replaceAll(RegExp(r'[àâä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[îï]'), 'i')
      .replaceAll(RegExp(r'[ôö]'), 'o')
      .replaceAll(RegExp(r'[ùûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return 'om_$cleaned';
}

/// UI customization, synced across devices through a dedicated IMAP
/// folder — [updatedAt] resolves conflicts (latest wins).
@freezed
abstract class AppPrefs with _$AppPrefs {
  const AppPrefs._();

  const factory AppPrefs({
    /// 'system' | 'light' | 'dark'
    @Default('system') String themeMode,

    /// ARGB value of the accent color.
    @Default(0xFF6D4AFF) int accentValue,

    /// Compact density: tighter list rows, no preview line.
    @Default(false) bool compact,

    /// Font family name, null = system default.
    String? fontFamily,

    /// Global text scale (0.85 – 1.3).
    @Default(1.0) double fontScale,

    /// Pane widths of the desktop layout (logical pixels).
    @Default(240.0) double sidebarWidth,
    @Default(380.0) double listWidth,

    /// Hide the reader pane: the list takes the full width and opening
    /// an email pushes a full-screen reader.
    @Default(false) bool hideReader,

    /// Privacy: remote images in HTML emails load only on demand.
    @Default(true) bool blockRemoteImages,

    /// Undo window before an email is actually sent (0 = immediate).
    @Default(10) int undoSendSeconds,

    /// User-defined labels (synced across devices like the rest).
    @Default([]) List<LabelDef> labels,

    /// Custom folder colors: IMAP path → ARGB value.
    @Default({}) Map<String, int> folderColors,
    @Default(0) int updatedAt,
  }) = _AppPrefs;

  factory AppPrefs.fromJson(Map<String, dynamic> json) =>
      _$AppPrefsFromJson(json);

  Color get accent => Color(accentValue);

  ThemeMode get materialThemeMode => switch (themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/// The accent choices offered in the appearance dialog.
const accentChoices = <(String, int)>[
  ('Violet', 0xFF6D4AFF),
  ('Océan', 0xFF2D7DD2),
  ('Émeraude', 0xFF13905F),
  ('Corail', 0xFFE85D75),
  ('Ambre', 0xFFD9822B),
  ('Graphite', 0xFF5F6472),
];

/// Font choices: label → family name (null = platform default).
/// Families resolve to their platform equivalents (serif/monospace are
/// generic and always available).
const fontChoices = <(String, String?)>[
  ('Système', null),
  ('Serif', 'serif'),
  ('Monospace', 'monospace'),
];
