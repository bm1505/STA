import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/ride_provider.dart';
import 'screens/admin_home_screen.dart';
import 'screens/admin_login_screen.dart';
import 'screens/admin_drivers_screen.dart';
import 'screens/admin_users_screen.dart';
import 'screens/admin_trip_history_screen.dart';
import 'screens/admin_settings_screen.dart';
import 'screens/admin_map_screen.dart';
import 'screens/admin_live_trips_screen.dart';
import 'screens/chat_screen.dart';
import 'utils/theme.dart';
import 'models/user.dart';
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
    }
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => AuthProvider()..checkAuthStatus()),
        ChangeNotifierProvider(create: (_) => RideProvider()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return MaterialApp(
            title: 'STA Admin Panel',
            theme: AppTheme.adminTheme, // Use Admin specific professional theme
            darkTheme: AppTheme.adminTheme,
            themeMode: ThemeMode.dark, // Admin always dark/premium
            debugShowCheckedModeBanner: false,
            home: _getLandingScreen(auth),
            routes: {
              '/admin-home': (context) => const AdminHomeScreen(),
              '/admin-drivers': (context) => const AdminDriversScreen(),
              '/admin-users': (context) => const AdminUsersScreen(),
              '/admin-history': (context) => const AdminTripHistoryScreen(),
              '/admin-settings': (context) => const AdminSettingsScreen(),
              '/admin-map': (context) => const AdminMapScreen(),
              '/admin-live-trips': (context) => const AdminLiveTripsScreen(),
            },
            onGenerateRoute: (settings) {
              if (settings.name == '/chat') {
                final args = settings.arguments as Map<String, dynamic>?;
                if (args == null) return null;
                return MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    receiverId: args['receiverId'],
                    receiverName: args['receiverName'],
                    senderId: args['senderId'],
                    senderName: args['senderName'] ?? 'Admin',
                  ),
                );
              }
              return null;
            },
          );
        },
      ),
    );
  }

  Widget _getLandingScreen(AuthProvider auth) {
    if (!auth.isAuthenticated) {
      return const AdminLoginScreen();
    }

    if (auth.currentUser?.role != UserRole.admin) {
      // If someone logged in but isn't an admin, force logout or show error
      Future.microtask(() => auth.logout());
      return const AdminLoginScreen();
    }

    return const AdminHomeScreen();
  }
}
