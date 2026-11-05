import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentService {
  static SupabaseClient get _db => Supabase.instance.client;

  /// Creates a payment request in Supabase. Actual payment initiation and
  /// provider credentials must be handled by a trusted server endpoint.
  static Future<Map<String, dynamic>> initiateCheckout({
    required String phone,
    required double amount,
    String? rideId,
    String userRole = 'rider',
  }) async {
    try {
      final user = _db.auth.currentUser;
      if (user == null) throw Exception('User not logged in');
      if (amount <= 0) throw Exception('Invalid payment amount');

      final row = await _db.from('payments').insert({
        'user_id': user.id,
        'phone_number': phone,
        'amount': amount,
        'status': 'pending',
        'ride_id': rideId,
        'type': rideId == null ? 'topup' : 'ride_payment',
        'user_role': userRole,
      }).select('id').single();

      return {
        'success': true,
        'paymentId': row['id'].toString(),
        'message': 'Payment request created. Awaiting secure payment processing.',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Stream<Map<String, dynamic>?> listenToPayment(String paymentId) {
    return _db
        .from('payments')
        .stream(primaryKey: ['id'])
        .eq('id', paymentId)
        .map((rows) => rows.isEmpty
            ? null
            : Map<String, dynamic>.from(rows.first));
  }

  static Future<Map<String, dynamic>> sendPayout({
    required String userId,
    required String phone,
    required double amount,
  }) async => {
    'success': false,
    'error': 'Payout processing must be configured on the trusted server.',
  };

  static Future<Map<String, dynamic>> sendAirtime({
    required String phone,
    required double amount,
  }) async => {
    'success': false,
    'error': 'Airtime processing must be configured on the trusted server.',
  };
}
