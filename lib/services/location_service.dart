import 'dart:async';
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

/// Background location collector for the driver app.
///
/// The background isolate only collects device location and forwards it to the
/// foreground app. Supabase writes are intentionally performed by
/// DriverRideProvider in the authenticated foreground isolate so the active
/// Supabase session and RLS context remain authoritative.
@pragma('vm:entry-point')
class LocationService {
  @pragma('vm:entry-point')
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'sta_location_channel',
        initialNotificationTitle: 'STA Driver Online',
        initialNotificationContent: 'Inatafuta eneo lako...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    // iOS background execution is controlled by the operating system.
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
      service.setForegroundNotificationInfo(
        title: 'STA Driver - Online',
        content: 'Mfumo wa eneo unaanza...',
      );

      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });

      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
    }

    StreamSubscription<Position>? positionSubscription;
    service.on('stopService').listen((event) {
      positionSubscription?.cancel();
      service.stopSelf();
    });
    positionSubscription = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 5),
      ),
    ).listen(
      (Position position) {
        // Forward only device telemetry. The foreground provider validates
        // the signed-in driver and persists it through Supabase RLS.
        service.invoke('update', {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'bearing': position.heading,
          'speed': position.speed,
          'accuracy': position.accuracy,
          'recordedAt': DateTime.now().toUtc().toIso8601String(),
        });

        if (service is AndroidServiceInstance) {
          service.isForegroundService().then((isForeground) {
            if (isForeground) {
              service.setForegroundNotificationInfo(
                title: 'STA Driver - Online',
                content: 'Upo tayari kupokea safari.',
              );
            }
          });
        }
      },
      onError: (Object error) {
        // Do not terminate the foreground service on a transient GPS error.
        service.invoke('locationError', {'message': error.toString()});
      },
      onDone: () {
        positionSubscription?.cancel();
      },
    );

  }
}
