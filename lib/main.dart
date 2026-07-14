import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models/prefs.dart';
import 'providers/config_provider.dart';
import 'providers/prefs_provider.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const ProviderScope(child: OpenMailboxApp()));
}

class OpenMailboxApp extends ConsumerWidget {
  const OpenMailboxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(prefsProvider).value ?? const AppPrefs();
    return MaterialApp(
      title: 'OpenMailbox',
      themeMode: prefs.materialThemeMode,
      theme: buildTheme(Brightness.light,
          accent: prefs.accent,
          compact: prefs.compact,
          fontFamily: prefs.fontFamily),
      darkTheme: buildTheme(Brightness.dark,
          accent: prefs.accent,
          compact: prefs.compact,
          fontFamily: prefs.fontFamily),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(prefs.fontScale),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _RootScreen(),
    );
  }
}

class _RootScreen extends ConsumerWidget {
  const _RootScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(accountConfigProvider);

    return configAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Erreur: $error')),
      ),
      data: (config) => config == null ? const SetupScreen() : const HomeScreen(),
    );
  }
}
