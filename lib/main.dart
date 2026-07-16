import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models/prefs.dart';
import 'providers/config_provider.dart';
import 'providers/prefs_provider.dart';
import 'services/foreground_mail_service.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // Start the UI immediately; notification + background setup run after,
  // each guarded so a plugin failure can never block startup.
  runApp(const ProviderScope(child: OpenMailboxApp()));
  initForegroundTask();
  _initBackground();
}

/// Fire-and-forget background wiring, ordered so notifications (and their
/// runtime permission) are ready before anything that posts them. Background
/// mail checking is opt-in: only when the user enabled instant notifications
/// do we start the foreground IMAP-IDLE watcher. Otherwise new mail shows
/// while the app is open (no persistent background connection — deliberately,
/// after WorkManager's auto-init repeatedly crashed the app at startup).
Future<void> _initBackground() async {
  await NotificationService.init().catchError((_) {});
  try {
    final prefs = await StorageService().loadPrefs();
    if (prefs.instantNotifications) {
      await startMailWatcher();
    }
  } catch (_) {
    // Instant mode is best-effort.
  }
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
