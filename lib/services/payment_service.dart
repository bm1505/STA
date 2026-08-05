import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PaymentService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Inaanza mchakato wa malipo kwa kuandika kwenye Firestore.
  /// Cloud Function itasikiliza hapa na kutuma STK Push.
  static Future<Map<String, dynamic>> initiateCheckout({
    required String phone,
    required double amount,
    String? rideId,
    String userRole = 'rider',
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      // Tunatengeneza document mpya kwenye 'payments'
      final docRef = await _db.collection('payments').add({
        'userId': user.uid,
        'phoneNumber': phone,
        'amount': amount,
        'status': 'pending',
        'rideId': rideId ?? 'topup',
        'type': rideId == null ? 'topup' : 'ride_payment',
        'userRole': userRole,
        'createdAt': FieldValue.serverTimestamp(),
      });

      return {
        'success': true,
        'paymentId': docRef.id,
        'message': 'STK Push initiated'
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Listen to payment status updates
  static Stream<DocumentSnapshot> listenToPayment(String paymentId) {
    return _db.collection('payments').doc(paymentId).snapshots();
  }

  // Mbinu hizi kwa sasa hazitumiki (Serverless migration)
  static Future<Map<String, dynamic>> sendPayout(
          {required String userId,
          required String phone,
          required double amount}) async =>
      {'success': false, 'error': 'Not implemented yet'};
  static Future<Map<String, dynamic>> sendAirtime(
          {required String phone, required double amount}) async =>
      {'success': false, 'error': 'Not implemented yet'};
}
