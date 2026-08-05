import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();
    await Firebase.initializeApp();

    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
      
      service.setForegroundNotificationInfo(
        title: "STA Driver - Online",
        content: "Mfumo wa eneo unaanza...",
      );

      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });

      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
    }

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    String? regionCache;
    String? vehicleTypeCache;

    Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 5),
      ),
    ).listen((Position position) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (regionCache == null || vehicleTypeCache == null) {
        final driverDoc = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(user.uid)
            .get();
        if (driverDoc.exists) {
          regionCache = driverDoc.data()?['region'] ?? 'Arusha';
          vehicleTypeCache = driverDoc.data()?['vehicleType'] ?? 'Car';
        }
      }

      await FirebaseFirestore.instance
          .collection('drivers_online')
          .doc(user.uid)
          .set({
        'id': user.uid,
        'lat': position.latitude,
        'lng': position.longitude,
        'bearing': position.heading,
        'lastUpdate': FieldValue.serverTimestamp(),
        'region': regionCache ?? 'Arusha',
        'vehicleType': vehicleTypeCache ?? 'Car',
      }, SetOptions(merge: true));

      service.invoke('update', {
        "latitude": position.latitude,
        "longitude": position.longitude,
        "bearing": position.heading,
      });

      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          service.setForegroundNotificationInfo(
            title: "STA Driver - Online",
            content: "Upo tayari kupokea safari.",
          );
        }
      }
    });
  }
}
