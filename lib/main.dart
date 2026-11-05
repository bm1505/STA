import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/ride_provider.dart';
import 'providers/driver_ride_provider.dart';
import 'screens/auth_option_screen.dart';
import 'screens/home_screen.dart';
import 'screens/driver_home_screen.dart';
import 'screens/about_screen.dart';
import 'screens/support_screen.dart';
import 'screens/promotions_screen.dart';
import 'screens/safety_screen.dart';
import 'screens/driver_auth_screen.dart';
import 'screens/driver_setup_profile_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/ride_request_screen.dart';
import 'screens/map_screen.dart';
import 'screens/rider_trip_history_screen.dart';
import 'screens/driver_trip_history_screen.dart';
import 'screens/wallet_screen.dart';
import 'screens/admin_home_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/driver_registration_flow.dart';
import 'screens/receipt_screen.dart';
import 'screens/location_picker_screen.dart';
import 'utils/theme.dart';
import 'models/user.dart';

import 'services/notification_service.dart';
import 'services/location_service.dart';
import 'services/sound_service.dart';
import 'services/postgres_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await StaSupabase.initialize();
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: String.fromEnvironment('FB_API_KEY'),
          authDomain: String.fromEnvironment('FB_AUTH_DOMAIN'),
          projectId: String.fromEnvironment('FB_PROJECT_ID'),
          storageBucket: String.fromEnvironment('FB_STORAGE_BUCKET'),
          messagingSenderId: String.fromEnvironment('FB_SENDER_ID'),
          appId: String.fromEnvironment('FB_APP_ID'),
          measurementId: String.fromEnvironment('FB_MEASUREMENT_ID'),
        ),
      );
    } else {
      await Firebase.initializeApp();
      await NotificationService.initialize();
      await LocationService.initializeService();
      // Hakikisha sauti na picha (service) zimeanza kabla ya UI
      await SoundService.initialize();
    }
    
    // Anzisha Postgres kwa ajili ya Picha (Presentation)
    if (!kIsWeb) {
      await PostgresService.instance.initializeDB().catchError((e) => debugPrint("Postgres Init Error: $e"));
    }
  } catch (e) {
    debugPrint("Initialization Error: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  final UserRole? initialRole;
  const MyApp({super.key, this.initialRole});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => AuthProvider()..checkAuthStatus()),
        ChangeNotifierProvider(create: (_) => RideProvider()),
        ChangeNotifierProvider(create: (_) => DriverRideProvider()),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return MaterialApp(
            title: 'STA Ride',
            theme: AppTheme.lightMidnightGoldTheme,
            darkTheme: AppTheme.midnightGoldTheme,
            themeMode: auth.themeMode,
            debugShowCheckedModeBanner: false,
            initialRoute: '/splash',
            onGenerateRoute: (settings) {
              if (settings.name == '/splash') {
                return MaterialPageRoute(
                    builder: (context) => SplashScreen(role: initialRole));
              }
              if (settings.name == '/') {
                return MaterialPageRoute(
                    builder: (context) => _getLandingScreen(auth));
              }
              if (settings.name == '/home') {
                if (initialRole == UserRole.driver) {
                  return MaterialPageRoute(builder: (context) => _getLandingScreen(auth));
                }
                return MaterialPageRoute(
                    builder: (context) =>
                        _getHomeScreenForRole(auth.currentUser, context));
              }
              if (settings.name == '/driver-home') {
                return MaterialPageRoute(
                    builder: (context) => const DriverHomeScreen());
              }
              if (settings.name == '/driver-auth') {
                return MaterialPageRoute(
                    builder: (context) => const DriverAuthScreen());
              }
              if (settings.name == '/driver-register-flow') {
                return MaterialPageRoute(
                    builder: (context) => const DriverRegistrationFlow());
              }
              if (settings.name == '/profile') {
                return MaterialPageRoute(
                    builder: (context) => const ProfileScreen());
              }
              if (settings.name == '/wallet') {
                return MaterialPageRoute(
                    builder: (context) => const WalletScreen());
              }
              if (settings.name == '/admin-home') {
                return MaterialPageRoute(
                    builder: (context) => const AdminHomeScreen());
              }
              if (settings.name == '/rider-history') {
                final args = settings.arguments as String?;
                return MaterialPageRoute(
                  builder: (context) =>
                      RiderTripHistoryScreen(riderId: args ?? ''),
                );
              }
              if (settings.name == '/driver-setup') {
                final args = settings.arguments as String?;
                return MaterialPageRoute(
                  builder: (context) =>
                      DriverSetupProfileScreen(driverId: args ?? ''),
                );
              }
              if (settings.name == '/driver-history') {
                final args = settings.arguments as String?;
                return MaterialPageRoute(
                  builder: (context) =>
                      DriverTripHistoryScreen(driverId: args ?? ''),
                );
              }
              if (settings.name == '/chat') {
                final args = settings.arguments as Map<String, dynamic>?;
                if (args == null) return null;
                return MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    receiverId: args['receiverId'] ?? '',
                    receiverName: args['receiverName'] ?? 'Chat',
                    senderId: args['senderId'] ?? '',
                    senderName: args['senderName'] ?? 'User',
                  ),
                );
              }
              if (settings.name == '/ride-request') {
                return MaterialPageRoute(
                  builder: (context) => const RideRequestScreen(),
                  settings: settings,
                );
              }
              if (settings.name == '/map') {
                final args = settings.arguments as Map<String, dynamic>?;
                return MaterialPageRoute(
                  builder: (context) => MapScreen(
                    vehicleType: args?['vehicleType'] ?? 'Car',
                    vehicle: args?['vehicle'],
                  ),
                );
              }
              if (settings.name == '/receipt') {
                final args = settings.arguments as Map<String, dynamic>?;
                if (args == null) return null;
                return MaterialPageRoute(
                  builder: (context) => ReceiptScreen(tripData: args),
                );
              }
              if (settings.name == '/support') {
                return MaterialPageRoute(builder: (context) => const SupportScreen());
              }
              if (settings.name == '/promotions') {
                return MaterialPageRoute(builder: (context) => const PromotionsScreen());
              }
              if (settings.name == '/safety') {
                return MaterialPageRoute(builder: (context) => const SafetyScreen());
              }
              if (settings.name == '/about') {
                return MaterialPageRoute(builder: (context) => const AboutScreen());
              }
              if (settings.name == '/location-picker') {
                final args = settings.arguments as Map<String, dynamic>?;
                return MaterialPageRoute(
                  builder: (context) => LocationPickerScreen(
                    title: args?['title'] ?? 'Select Location',
                    initialLocation: args?['initialLocation'],
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
    if (auth.isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF121212), Colors.black],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 130,
                width: 130,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGold,
                  borderRadius: BorderRadius.circular(35),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryGold.withOpacity(0.2),
                      blurRadius: 30,
                      spreadRadius: 10,
                    )
                  ],
                ),
                child: const Icon(
                  Icons.directions_car_filled_rounded,
                  size: 80,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 30),
              Text(
                "STA RIDE",
                style: GoogleFonts.poppins(
                  color: AppTheme.primaryGold,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                ),
              ),
              const SizedBox(height: 60),
              const CircularProgressIndicator(
                color: AppTheme.primaryGold,
                strokeWidth: 2,
              ),
            ],
          ),
        ),
      );
    }

    if (initialRole != null) {
      if (auth.isAuthenticated) {
        if (auth.currentUser?.role != initialRole) {
          Future.microtask(() => auth.logout());
          return _getLoginScreenForRole(initialRole!);
        }
        return _getHomeScreenForRole(auth.currentUser, null);
      } else {
        return _getLoginScreenForRole(initialRole!);
      }
    }

    if (!auth.isAuthenticated) return const AuthOptionScreen();
    return _getHomeScreenForRole(auth.currentUser, null);
  }

  Widget _getLoginScreenForRole(UserRole role) {
    switch (role) {
      case UserRole.driver:
        return const DriverAuthScreen();
      default:
        return const AuthOptionScreen();
    }
  }

  Widget _getHomeScreenForRole(UserModel? user, BuildContext? context) {
    if (user == null) return const AuthOptionScreen();

    if (initialRole != null && user.role != initialRole) {
      if (context != null) {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        Future.microtask(() => auth.logout());
      }
      return _getLoginScreenForRole(initialRole!);
    }

    final bool isStaff = user.role == UserRole.admin ||
        user.role == UserRole.it ||
        user.role == UserRole.support;

    if (!isStaff && !user.isProfileComplete) {
      if (user.role == UserRole.driver) {
        return const DriverRegistrationFlow();
      } else {
        return const ProfileScreen(mustCompleteProfile: true);
      }
    }

    switch (user.role) {
      case UserRole.driver:
        return const DriverHomeScreen();
      case UserRole.admin:
      case UserRole.it:
      case UserRole.support:
        return const AdminHomeScreen();
      default:
        return const HomeScreen();
    }
  }
}
