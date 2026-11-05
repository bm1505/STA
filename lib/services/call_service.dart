import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

/// Call signalling metadata is stored with the active ride in Supabase.
class CallService {
  static const String appId = "39c388815a804bc58a43fd527c7b0b73";
  static SupabaseClient get _supabase => Supabase.instance.client;

  static Future<bool> handlePermissions() async {
    final statuses = await [
      Permission.microphone,
      Permission.phone,
    ].request();
    return statuses[Permission.microphone] == PermissionStatus.granted;
  }

  static Future<void> updateCallStatus(
    String rideId,
    String? status, {
    String? callerName,
    String? callerId,
  }) async {
    final activeCall = status == null
        ? null
        : {
            'status': status,
            'callerName': callerName,
            'callerId': callerId,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          };

    await _supabase.from('ride_requests').update({
      'active_call': activeCall,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', rideId);
  }

  static Stream<Map<String, dynamic>?> listenToCall(String rideId) {
    return _supabase
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('id', rideId)
        .map((rows) => rows.isEmpty
            ? null
            : Map<String, dynamic>.from(rows.first));
  }
}
