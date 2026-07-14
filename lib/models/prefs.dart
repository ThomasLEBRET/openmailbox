import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'prefs.freezed.dart';
part 'prefs.g.dart';

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
