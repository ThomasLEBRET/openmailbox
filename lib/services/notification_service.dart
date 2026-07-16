import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Native notifications (macOS / Android) for new-mail alerts, with the
/// unread count mirrored on the app badge where the platform supports it.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  // Single channel for new-mail alerts. Created explicitly at init() so it
  // shows up in Android's per-app notification settings right away (Android
  // 8+ hides an app from settings until at least one channel exists).
  static const _channelId = 'new_mail';
  static const _channelName = 'Nouveaux messages';

  static Future<void> init() async {
    if (_ready) return;
    const settings = InitializationSettings(
      macOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: false,
      ),
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    try {
      await _plugin.initialize(settings: settings);
      // Android 13+ needs an explicit runtime request for POST_NOTIFICATIONS
      // (Darwin permissions are asked via the init settings above).
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        // Its own try/catch: requesting the runtime permission needs a
        // foreground Activity and throws in a background/foreground-service
        // isolate. That must not abort init — the permission is already
        // granted there, and the channel + _ready still need to be set up,
        // otherwise the service could never post a notification.
        try {
          await android?.requestNotificationsPermission();
        } catch (_) {}
        // Pre-create the channel (idempotent) rather than relying on it being
        // created lazily on the first notification.
        await android?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            importance: Importance.high,
          ),
        );
      }
      _ready = true;
    } catch (_) {
      // Notifications unavailable (permission denied, headless test…) —
      // the app works without them.
    }
  }

  static Future<void> notifyNewMail(int newCount, int unreadTotal) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: 1,
        title: 'OpenMailbox',
        body: newCount == 1
            ? 'Nouveau message dans votre boîte de réception'
            : '$newCount nouveaux messages dans votre boîte de réception',
        notificationDetails: NotificationDetails(
          macOS: DarwinNotificationDetails(badgeNumber: unreadTotal),
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            // Badge count on launchers that support it.
            number: unreadTotal,
          ),
        ),
      );
    } catch (_) {
      // Best-effort.
    }
  }
}
