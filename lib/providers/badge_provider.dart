import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'folder_provider.dart';

/// Keeps the app-icon badge in sync with the total unread count across
/// every folder. Read it once (from the home screen) to start it.
final badgeUpdaterProvider = Provider<void>((ref) {
  ref.listen<int>(
    folderListProvider.select(
      (async) => (async.value ?? const [])
          .fold<int>(0, (sum, folder) => sum + folder.unread),
    ),
    (previous, total) => _setBadge(total),
    fireImmediately: true,
  );
});

Future<void> _setBadge(int total) async {
  try {
    if (!await AppBadgePlus.isSupported()) return;
    AppBadgePlus.updateBadge(total);
  } catch (_) {
    // Badge unsupported on this platform/launcher — ignore.
  }
}
