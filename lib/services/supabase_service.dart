import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Central Supabase bootstrap for STA.
///
/// Configure with --dart-define=SUPABASE_URL=... and
/// --dart-define=SUPABASE_ANON_KEY=... . Never embed a service_role key.
class StaSupabase {
  StaSupabase._();
  static const String _url = String.fromEnvironment('SUPABASE_URL');
  static const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static bool _initialized = false;

  static bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;
  static bool get isInitialized => _initialized;

  static SupabaseClient get client {
    if (!_initialized) {
      throw StateError('Supabase is not initialized. Configure SUPABASE_URL and SUPABASE_ANON_KEY.');
    }
    return Supabase.instance.client;
  }

  static Future<bool> initialize() async {
    if (_initialized) return true;
    if (!isConfigured) {
      debugPrint('STA Supabase configuration is missing.');
      return false;
    }
    await Supabase.initialize(url: _url, anonKey: _anonKey, debug: kDebugMode);
    _initialized = true;
    return true;
  }
}
