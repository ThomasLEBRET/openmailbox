import 'package:flutter/material.dart';

/// Design tokens for the ProtonMail-inspired look: deep purple accent,
/// dark aubergine sidebar, generous whitespace.
abstract class AppColors {
  static const primary = Color(0xFF6D4AFF);
  static const sidebarBackground = Color(0xFF1E1A2E);
  static const sidebarText = Color(0xB3FFFFFF); // white 70%
  static const sidebarTextSelected = Colors.white;

  /// Avatar palette, picked by hash of the sender address.
  static const avatarColors = [
    Color(0xFF6D4AFF),
    Color(0xFF0E918C),
    Color(0xFFDB6D28),
    Color(0xFFC44569),
    Color(0xFF3867D6),
    Color(0xFF20835B),
    Color(0xFF8854D0),
    Color(0xFFB33939),
  ];

  static Color avatarColorFor(String seed) =>
      avatarColors[seed.hashCode.abs() % avatarColors.length];
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor:
        brightness == Brightness.light ? Colors.white : const Color(0xFF16141F),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.4),
      space: 1,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
  );
}

/// "14:32" today, "5 juil." this year, "13/07/2025" otherwise.
String formatEmailDate(DateTime date) {
  const months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];
  final now = DateTime.now();
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
  if (date.year == now.year) {
    return '${date.day} ${months[date.month - 1]}';
  }
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}
