import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'main.dart';
import 'models/user.dart';
import 'services/notification_service.dart';
import 'services/location_service.dart';
import 'services/postgres_service.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await StaSupabase.initialize();
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyC3IaXrGR6U0DppCb_YKHpFZOHYf6CyjhM",
          authDomain: "smart-transport-app-7fbde.firebaseapp.com",
          projectId: "smart-transport-app-7fbde",
          storageBucket: "smart-transport-app-7fbde.firebasestorage.app",
          messagingSenderId: "463369496285",
          appId: "1:463369496285:web:c45bf547161b2a39f75d34",
          measurementId: "G-W12HWEE52X",
        ),
      );
    } else {
      await Firebase.initializeApp();
      await NotificationService.initialize();
      await LocationService.initializeService();
      
      // Anzisha Postgres kwa ajili ya Picha (Presentation)
      PostgresService.instance.initializeDB().catchError((e) => debugPrint("Postgres Init Error: $e"));
    }

    // Database Cleanup (Disabled)
    // await DatabaseService.instance.clearAllUsersExceptAdmin();
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  runApp(const MyApp(initialRole: UserRole.rider));
}
