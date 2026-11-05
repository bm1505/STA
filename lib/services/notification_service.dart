import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Local notification presentation for STA.
///
/// Remote delivery will be connected to the Supabase-backed notification
/// endpoint after the server-side delivery provider is configured.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel highImportanceChannel =
      AndroidNotificationChannel(
    'sta_high_importance_channel',
    'STA Notifications',
    description: 'Ride requests and important account alerts.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel locationChannel =
      AndroidNotificationChannel(
    'sta_location_channel',
    'STA Location Service',
    description: 'Driver location service status.',
    importance: Importance.low,
    playSound: false,
  );

  static Future<void> initialize() async {
    if (kIsWeb) {
      debugPrint('Local notifications are not initialized on Web.');
      return;
    }

    try {
      final permission = await Permission.notification.status;
      if (permission.isDenied) {
        await Permission.notification.request();
      }

      final androidPlugin = _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.createNotificationChannel(highImportanceChannel);
      await androidPlugin?.createNotificationChannel(locationChannel);

      const initializationSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );

      await _localNotificationsPlugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: (details) {
          debugPrint('Notification tapped: ${details.payload}');
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Notification initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'sta_high_importance_channel',
        'STA Notifications',
        channelDescription: 'Ride requests and important account alerts.',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _localNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}
