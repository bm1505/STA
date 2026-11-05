import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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

    // Database Cleanup (Disabled)
    // await DatabaseService.instance.clearAllUsersExceptAdmin();
  } catch (e) {
    debugPrint("Startup initialization error: $e");
  }

  runApp(const MyApp(initialRole: UserRole.rider));
}
