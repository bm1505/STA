import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'main.dart';
import 'models/user.dart';
import 'services/notification_service.dart';
import 'services/location_service.dart';
import 'services/sound_service.dart';
import 'services/postgres_service.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await StaSupabase.initialize();

    // Initialize Sound Service
    await SoundService.initialize().catchError((e) => debugPrint("Sound Error: $e"));

    // Initialize Postgres for images (Presentation)
    if (!kIsWeb) {
      await PostgresService.instance.initializeDB().catchError((e) => debugPrint("Postgres Init Error: $e"));
    }

    // IKIWA UNATAKA KUFUTA WATUMIAJI WOTE ISIPOKUWA ADMIN,
    // ONDOA '//' KWENYE MSTARI ULIOPO CHINI, KISHA RUN APP MARA MOJA.
    // await DatabaseService.instance.clearAllUsersExceptAdmin();
  } catch (e) {
    debugPrint("Startup initialization error: $e");
  }

  runApp(const MyApp(initialRole: UserRole.driver));
}
