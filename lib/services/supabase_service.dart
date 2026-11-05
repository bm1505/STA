import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Central Supabase bootstrap for STA.
///
/// Configure at build time:
/// --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co
/// --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_ANON_KEY
///
/// Never place a service_role key in the Flutter application.
class StaSupabase {
  StaSupabase._();

  static const String _url = String.fromEnvironment('SUPABASE_URL');
  static const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;
  static bool get isInitialized => isConfigured && _initialized;
  static bool _initialized = false;

  static SupabaseClient get client {
    if (!isInitialized) {
      throw StateError(
        'STA Supabase is not initialized. Configure SUPABASE_URL and SUPABASE_ANON_KEY.',
      );
    }
    return Supabase.instance.client;
  }

  static Future<bool> initialize() async {
    if (_initialized) return true;
    if (!isConfigured) {
      debugPrint(
        'STA Supabase is not configured. Supply SUPABASE_URL and SUPABASE_ANON_KEY.',
      );
      return false;
    }

    await Supabase.initialize(
      url: _url,
      anonKey: _anonKey,
      debug: kDebugMode,
    );
    _initialized = true;
    return true;
  }
}
