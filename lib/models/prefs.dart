import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'email.dart';

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

    /// Mobile swipe actions on a list row ([SwipeAction] names).
    @Default('read') String swipeRightAction,
    @Default('delete') String swipeLeftAction,

    /// Android only: keep a foreground service holding an IMAP IDLE
    /// connection so new mail notifies near-instantly (app closed), at the
    /// cost of a persistent notification. Off = periodic 15-min check only.
    @Default(false) bool instantNotifications,

    /// Email list sort order ([SortMode] names).
    @Default('dateDesc') String sortMode,

    /// Auto-empty the trash of messages older than this many days
    /// (0 = never).
    @Default(0) int autoEmptyTrashDays,
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

  SwipeAction get swipeRight => SwipeAction.fromName(swipeRightAction);
  SwipeAction get swipeLeft => SwipeAction.fromName(swipeLeftAction);
  SortMode get sort => SortMode.fromName(sortMode);
}

/// Sort order for the email list. All are applied locally on the cached
/// list, so they're free (no extra server round trip).
enum SortMode {
  dateDesc('dateDesc', 'Plus récents d\'abord', Icons.arrow_downward_rounded),
  dateAsc('dateAsc', 'Plus anciens d\'abord', Icons.arrow_upward_rounded),
  unreadFirst('unreadFirst', 'Non lus d\'abord', Icons.mark_email_unread_outlined),
  sender('sender', 'Expéditeur (A→Z)', Icons.person_outline_rounded);

  const SortMode(this.name, this.label, this.icon);

  final String name;
  final String label;
  final IconData icon;

  /// Orders [emails] a new list according to this mode. Date descending is
  /// the tiebreaker so groups stay chronological.
  List<Email> apply(List<Email> emails) {
    final sorted = [...emails];
    switch (this) {
      case SortMode.dateDesc:
        sorted.sort((a, b) => b.date.compareTo(a.date));
      case SortMode.dateAsc:
        sorted.sort((a, b) => a.date.compareTo(b.date));
      case SortMode.unreadFirst:
        sorted.sort((a, b) {
          if (a.isRead != b.isRead) return a.isRead ? 1 : -1;
          return b.date.compareTo(a.date);
        });
      case SortMode.sender:
        sorted.sort((a, b) {
          final byName =
              a.from.toLowerCase().compareTo(b.from.toLowerCase());
          return byName != 0 ? byName : b.date.compareTo(a.date);
        });
    }
    return sorted;
  }

  static SortMode fromName(String name) => SortMode.values
      .firstWhere((s) => s.name == name, orElse: () => SortMode.dateDesc);
}

/// A configurable swipe gesture on a mobile email row.
enum SwipeAction {
  none('none', 'Aucune', Icons.block, Colors.grey),
  read('read', 'Lu / Non lu', Icons.mark_email_read_outlined,
      Color(0xFF2D7DD2)),
  flag('flag', 'Étoile', Icons.star_rounded, Color(0xFFF2B01E)),
  delete('delete', 'Supprimer', Icons.delete_outline_rounded,
      Color(0xFFE05260)),
  move('move', 'Déplacer', Icons.drive_file_move_outlined, Color(0xFF6D4AFF));

  const SwipeAction(this.name, this.label, this.icon, this.color);

  final String name;
  final String label;
  final IconData icon;
  final Color color;

  /// True when performing the action removes the row from the list.
  bool get isDestructive => this == delete || this == move;

  static SwipeAction fromName(String name) =>
      SwipeAction.values.firstWhere((a) => a.name == name,
          orElse: () => SwipeAction.none);
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
