import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Handling a background message: ${message.messageId}");
}

class NotificationService {
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    if (kIsWeb) {
      debugPrint("Skipping mobile notification initialization on Web");
      return;
    }

    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Get and save device token
    String? token = await getDeviceToken();
    if (token != null) {
      debugPrint("FCM Token: $token");
      // Note: Ideally this should be saved via AuthProvider, but we can do it here too if needed
    }

    // Request permission for iOS/Android 13+ using permission_handler for better compatibility
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // Android notification channels
    const AndroidNotificationChannel highImportanceChannel =
        AndroidNotificationChannel(
      'sta_high_importance_channel',
      'STA High Importance Notifications',
      description: 'This channel is used for ride requests and alerts.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    const AndroidNotificationChannel locationChannel =
        AndroidNotificationChannel(
      'sta_location_channel', // Hii lazima ifanane na ile ya kwenye LocationService
      'STA Location Service',
      description: 'Inatumika kufuatilia eneo la dereva akiwa online.',
      importance:
          Importance.low, // Location updates hazihitaji kupiga kelele kila mara
      playSound: false,
    );

    final androidPlugin =
        _localNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(highImportanceChannel);
    await androidPlugin?.createNotificationChannel(locationChannel);

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _localNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        // Handle notification tap
        debugPrint("Notification tapped: ${details.payload}");
      },
    );

    // Listen to foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        _localNotificationsPlugin.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              highImportanceChannel.id,
              highImportanceChannel.name,
              channelDescription: highImportanceChannel.description,
              icon: android.smallIcon,
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              ticker: 'ticker',
            ),
          ),
          payload: message.data.toString(),
        );
      }
    });

    // Handle initial message when app is opened from terminated state
    RemoteMessage? initialMessage =
        await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint("App opened from initial message: ${initialMessage.data}");
    }

    // Handle messages when app is in background but not terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint(
          "App opened from background via notification: ${message.data}");
    });
  }

  static Future<String?> getDeviceToken() async {
    try {
      if (kIsWeb) return null;

      // Only proceed for mobile platforms
      if (!(Platform.isAndroid || Platform.isIOS)) return null;

      if (Platform.isIOS) {
        String? apnsToken = await _firebaseMessaging.getAPNSToken();
        if (apnsToken == null) return null;
      }
      return await _firebaseMessaging.getToken();
    } catch (e) {
      debugPrint("Error getting device token: $e");
      return null;
    }
  }
}
