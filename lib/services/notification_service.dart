import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Native notifications (macOS / Android) for new-mail alerts, with the
/// unread count mirrored on the app badge where the platform supports it.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

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
          android: const AndroidNotificationDetails(
            'new_mail',
            'Nouveaux messages',
            importance: Importance.defaultImportance,
          ),
        ),
      );
    } catch (_) {
      // Best-effort.
    }
  }
}
