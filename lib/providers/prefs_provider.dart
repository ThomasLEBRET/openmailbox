import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/prefs.dart';
import 'config_provider.dart';
import 'imap_session.dart';

/// UI preferences: applied from local storage instantly, then reconciled
/// with the copy synced in the account's IMAP folder (latest wins), so
/// the macOS and Android apps share the same look.
class PrefsNotifier extends AsyncNotifier<AppPrefs> {
  @override
  Future<AppPrefs> build() async {
    final local = await ref.read(storageServiceProvider).loadPrefs();
    _pullRemote(local);
    return local;
  }

  /// Best-effort background pull — a newer copy on the server (e.g.
  /// changed on the phone) replaces the local one.
  Future<void> _pullRemote(AppPrefs local) async {
    try {
      final json = await withImapSession(
          ref, (imap) => imap.fetchPrefsJson(),
          background: true);
      if (json == null) return;
      final remote =
          AppPrefs.fromJson(jsonDecode(json) as Map<String, dynamic>);
      if (remote.updatedAt > local.updatedAt) {
        await ref.read(storageServiceProvider).savePrefs(remote);
        state = AsyncData(remote);
      }
    } catch (_) {
      // No account yet, offline, or folder missing — local prefs stand.
    }
  }

  static const _unsetFont = 'UNSET';

  Future<void> apply({
    String? themeMode,
    int? accentValue,
    bool? compact,
    String? fontFamily = _unsetFont,
    double? fontScale,
    double? sidebarWidth,
    double? listWidth,
    bool? hideReader,
    bool? blockRemoteImages,
    int? undoSendSeconds,
  }) async {
    final current = state.value ?? const AppPrefs();
    final next = current.copyWith(
      themeMode: themeMode ?? current.themeMode,
      accentValue: accentValue ?? current.accentValue,
      compact: compact ?? current.compact,
      // fontFamily distinguishes "not passed" (sentinel) from an explicit
      // null, which means "back to the system font".
      fontFamily:
          identical(fontFamily, _unsetFont) ? current.fontFamily : fontFamily,
      fontScale: fontScale ?? current.fontScale,
      sidebarWidth: sidebarWidth ?? current.sidebarWidth,
      listWidth: listWidth ?? current.listWidth,
      hideReader: hideReader ?? current.hideReader,
      blockRemoteImages: blockRemoteImages ?? current.blockRemoteImages,
      undoSendSeconds: undoSendSeconds ?? current.undoSendSeconds,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    state = AsyncData(next);
    await ref.read(storageServiceProvider).savePrefs(next);
    // Push to the server in the background; next launch pulls it back
    // on any device.
    try {
      final json = jsonEncode(next.toJson());
      await withImapSession(ref, (imap) => imap.pushPrefsJson(json),
          background: true);
    } catch (_) {
      // Offline — the local copy still applies; sync happens next time.
    }
  }
}

final prefsProvider = AsyncNotifierProvider<PrefsNotifier, AppPrefs>(
  PrefsNotifier.new,
);
