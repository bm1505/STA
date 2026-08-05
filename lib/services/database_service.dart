import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import 'sound_service.dart';
import 'postgres_service.dart';
import 'otp_service.dart';
import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _uploadcarePubKey = '70eabc59a303435eb281';

  final Map<String, Stream<dynamic>> _streamCache = {};

  DatabaseService._() {
    if (kIsWeb) {
      try {
        _db.settings = const Settings(
          persistenceEnabled: false,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      } catch (e) {
        debugPrint("Firestore settings already applied: $e");
      }
    }
  }

  Stream<T> _getPersistentStream<T>(String key, Stream<T> Function() factory) {
    if (!_streamCache.containsKey(key) || _streamCache[key] == null) {
      _streamCache[key] = factory().asBroadcastStream(
        onCancel: (subscription) {
          subscription.cancel();
          _streamCache.remove(key);
        },
      );
    }
    return _streamCache[key] as Stream<T>;
  }

  bool isMasterAdmin(String email) {
    return email.toLowerCase() == 'admin@sta.co.tz' || email.toLowerCase() == 'mahega@sta.co.tz';
  }

  Future<UserModel?> getUser(String id, {UserRole? expectedRole}) async {
    try {
      if (isMasterAdmin(id)) {
        return UserModel(id: 'master_admin', name: 'System Admin', email: 'admin@sta.co.tz', role: UserRole.admin, phoneNumber: '0000000000', createdAt: DateTime.now());
      }
      for (var col in ['riders', 'drivers', 'staff']) {
        final doc = await _db.collection(col).doc(id).get();
        if (doc.exists) return UserModel.fromJson({...doc.data()!, 'id': doc.id});
        final q = await _db.collection(col).where('email', isEqualTo: id.toLowerCase()).limit(1).get();
        if (q.docs.isNotEmpty) return UserModel.fromJson({...q.docs.first.data(), 'id': q.docs.first.id});
      }
    } catch (e) {}
    return null;
  }

  Future<void> saveUser(UserModel user) async {
    String col = user.role == UserRole.driver ? 'drivers' : 'riders';
    await _db.collection(col).doc(user.id).set(user.toJson(), SetOptions(merge: true));
  }

  Future<bool> sendEmailOTP(String email, {String name = "User"}) async {
    try {
      return await OtpService.sendEmailOtp(email, name);
    } catch (e) {
      debugPrint("OTP Error: $e");
      return false;
    }
  }

  Future<bool> verifyEmailOTP(String email, String otp) async {
    return OtpService.verifyOtp(otp);
  }

  Future<void> incrementDriverRides(String driverId) async {
    await _db.collection('drivers').doc(driverId).update({
      'totalRides': FieldValue.increment(1),
    });
  }

  Future<String> uploadDriverDocument(String userId, String type, dynamic file) async {
    // Compatibility wrapper for named parameters if called that way (though Dart positional is strict)
    return _uploadDocInternal(userId, type, file);
  }

  Future<String> _uploadDocInternal(String userId, String type, dynamic file) async {
    try {
      String url = "";
      Uint8List? bytes;

      // 1. Pata bytes za picha
      if (file is Uint8List) {
        bytes = file;
      } else if (file is File) {
        bytes = await file.readAsBytes();
      } else if (file is String && !file.startsWith('http')) {
        bytes = await File(file).readAsBytes();
      }

      if (bytes == null) return "";

      // 2. Tuma kwenye PostgreSQL
      if (kIsWeb) {
        // Kwenye Web, tumia http.post ya kawaida kutuma Bytes HALISI (bila Multipart garbage)
        final uri = Uri.parse('http://localhost:3000/upload');
        final response = await http.post(
          uri,
          headers: {
            'x-user-id': userId,
            'x-file-type': type,
            'Content-Type': 'application/octet-stream',
          },
          body: bytes,
        );
        
        if (response.statusCode == 200) {
          url = 'pg://$userId/$type';
        } else {
          debugPrint("Proxy upload failed: ${response.statusCode}");
        }
      } else {
        // Kwenye Simu, tumia PostgresService moja kwa moja
        // Hakikisha PostgresService inatumia IP ya 192.168.1.103
        url = await PostgresService.instance.uploadFile(userId, type, bytes);
      }

      // 3. Update Firestore na URL ya pg://
      String field = '';
      String t = type.toLowerCase();
      if (t.contains('license')) field = 'licenseUrl';
      else if (t.contains('insurance')) field = 'insuranceUrl';
      else if (t.contains('national') || t.contains('nida')) field = 'nationalIdUrl';
      else if (t.contains('vehicle')) field = 'vehiclePhotoUrl';
      else if (t.contains('profile')) field = 'profileImageUrl';

      if (field.isNotEmpty && url.isNotEmpty) {
        // Jaribu kuupdate pande zote mbili (Rider au Driver) bila kusababisha crash
        try {
          final userDoc = await _db.collection('drivers').doc(userId).get();
          if (userDoc.exists) {
            await _db.collection('drivers').doc(userId).update({field: url});
          } else {
            await _db.collection('riders').doc(userId).update({field: url});
          }
        } catch (e) {
          debugPrint("Firestore update error: $e");
        }
      }
      return url;
    } catch (e) {
      debugPrint("Upload error: $e");
      return "";
    }
  }

  Future<void> updateAnyUserProfilePic(String userId, String url) async {
    try {
      // Jaribu kwanza kwenye riders
      final riderDoc = await _db.collection('riders').doc(userId).get();
      if (riderDoc.exists) {
        await _db.collection('riders').doc(userId).update({'profileImageUrl': url});
        return;
      }
      // Kama hayupo riders, update drivers
      await _db.collection('drivers').doc(userId).update({'profileImageUrl': url});
    } catch (e) {
      debugPrint("Error updating profile pic: $e");
    }
  }

  Future<void> updateDriverVerificationStatus(String id, dynamic status, {String? reason, bool isUpdate = false}) async {
    String statusStr = status is VerificationStatus ? status.toString().split('.').last : status.toString();
    
    if (isUpdate) {
      if (statusStr == 'verified') {
        // Approve pending updates
        final doc = await _db.collection('drivers').doc(id).get();
        final data = doc.data();
        if (data != null && data['pendingUpdates'] != null) {
          Map<String, dynamic> updates = Map<String, dynamic>.from(data['pendingUpdates']);
          updates['profileEditStatus'] = 'none';
          updates['pendingUpdates'] = FieldValue.delete();
          await _db.collection('drivers').doc(id).update(updates);
        }
      } else {
        // Reject pending updates
        await _db.collection('drivers').doc(id).update({
          'profileEditStatus': 'none',
          'pendingUpdates': FieldValue.delete(),
          if (reason != null) 'rejectionReason': reason,
        });
      }
    } else {
      // Standard new registration verification
      await _db.collection('drivers').doc(id).update({
        'verificationStatus': statusStr,
        'isVerified': statusStr == 'verified',
        if (reason != null) 'rejectionReason': reason,
      });
    }
  }

  Future<void> recordTrip(Map<String, dynamic> tripData) async {
    final String tripId = tripData['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
    final String? driverId = tripData['driverId'];
    if (driverId == null) return;

    await _db.runTransaction((transaction) async {
      double fare = (tripData['fare'] as num?)?.toDouble() ?? 0.0;
      String method = (tripData['paymentMethod'] ?? tripData['payment_method'] ?? 'cash').toString().toLowerCase();
      bool isCash = method == 'cash';
      
      double commission = (fare * 0.20).roundToDouble();
      double driverShare = (fare * 0.80).roundToDouble();

      // Hifadhi mahesabu kwenye Trip Document pia kwa ajili ya ripoti
      Map<String, dynamic> updatedTripData = {
        ...tripData,
        'commission': commission,
        'driverShare': driverShare,
        'processedAt': FieldValue.serverTimestamp(),
      };

      final tripRef = _db.collection('trips').doc(tripId);
      final tripSnap = await transaction.get(tripRef);

      if (tripSnap.exists) {
        final existingData = tripSnap.data() as Map<String, dynamic>;
        // KUZUIA: Tusije tuka-overwrite 'paid' na 'completed' (downstream sync)
        if (existingData['paymentStatus'] == 'paid' || existingData['status'] == 'paid' || existingData['status'] == 'completed_paid') {
          updatedTripData['paymentStatus'] = 'paid';
          if (updatedTripData['status'] == 'completed') {
            updatedTripData['status'] = existingData['status'];
          }
        }
        transaction.update(tripRef, updatedTripData);
      } else {
        transaction.set(tripRef, updatedTripData);
      }
      
      final walletRef = _db.collection('wallets').doc(driverId);
      
      if (isCash) {
        // Dereva anachukua cash yote, anakatwa 20% kwenye wallet (deni)
        transaction.set(walletRef, {
          'balance': FieldValue.increment(-commission), 
          'lastUpdated': FieldValue.serverTimestamp()
        }, SetOptions(merge: true));
        
        transaction.set(_db.collection('transactions').doc(), {
          'driverId': driverId, 
          'amount': -commission, 
          'type': 'commission_deduction', 
          'description': 'Trip Commission (Cash)', 
          'rideId': tripId, 
          'timestamp': FieldValue.serverTimestamp()
        });
      } else {
        // Pesa imekuja kwako (App), dereva anapewa 80% kwenye wallet yake (chumo)
        transaction.set(walletRef, {
          'balance': FieldValue.increment(driverShare), 
          'totalEarned': FieldValue.increment(driverShare), 
          'lastUpdated': FieldValue.serverTimestamp()
        }, SetOptions(merge: true));
        
        transaction.set(_db.collection('transactions').doc(), {
          'driverId': driverId, 
          'amount': driverShare, 
          'type': 'ride_earning', 
          'description': 'Trip Earnings (Digital)', 
          'rideId': tripId, 
          'timestamp': FieldValue.serverTimestamp()
        });
      }
    });
  }

  Stream<Map<String, dynamic>?> getWalletStream(String userId) {
    return _getPersistentStream('wallet_$userId', () => _db.collection('wallets').doc(userId).snapshots().map((doc) => doc.data()));
  }

  Stream<List<Map<String, dynamic>>> getTransactionsStream(String userId) {
    return _getPersistentStream('tx_$userId', () => _db.collection('transactions').where('driverId', isEqualTo: userId).snapshots().map((snap) {
        final docs = snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
        docs.sort((a, b) => ((b['timestamp'] as Timestamp?)?.seconds ?? 0).compareTo((a['timestamp'] as Timestamp?)?.seconds ?? 0));
        return docs.take(30).toList();
      })
    );
  }

  Stream<List<Map<String, dynamic>>> getPendingRequestsStream(String userId) {
    return _getPersistentStream('pending_req_$userId', () {
      final controller = StreamController<List<Map<String, dynamic>>>();
      StreamSubscription? pSub, wSub;
      List<Map<String, dynamic>> lastP = [], lastW = [];
      void emit() { if (!controller.isClosed) { final all = [...lastP, ...lastW]; all.sort((a, b) => ((b['createdAt'] as Timestamp?)?.seconds ?? 0).compareTo((a['createdAt'] as Timestamp?)?.seconds ?? 0)); controller.add(all); } }
      pSub = _db.collection('payments').where('userId', isEqualTo: userId).where('status', isEqualTo: 'pending').snapshots().listen((s) { lastP = s.docs.map((d) => ({...d.data(), 'id': d.id, 'type': 'topup', 'isPending': true})).toList(); emit(); });
      wSub = _db.collection('withdrawals').where('userId', isEqualTo: userId).where('status', isEqualTo: 'pending').snapshots().listen((s) { lastW = s.docs.map((d) => ({...d.data(), 'id': d.id, 'type': 'withdrawal', 'isPending': true})).toList(); emit(); });
      controller.onCancel = () { pSub?.cancel(); wSub?.cancel(); };
      return controller.stream;
    });
  }

  Stream<List<UserModel>> getDriversStream() {
    return _db.collection('drivers').snapshots().map((snap) => snap.docs.map((doc) => UserModel.fromJson({...doc.data(), 'id': doc.id})).toList());
  }

  Future<List<UserModel>> getAllDrivers() async {
    final snap = await _db.collection('drivers').get();
    return snap.docs.map((doc) => UserModel.fromJson({...doc.data(), 'id': doc.id})).toList();
  }

  Future<List<UserModel>> getAllUsers() async {
    final riders = await _db.collection('riders').get();
    final drivers = await _db.collection('drivers').get();
    final staff = await _db.collection('staff').get();
    List<UserModel> all = [];
    all.addAll(riders.docs.map((d) => UserModel.fromJson({...d.data(), 'id': d.id, 'role': 'rider'})));
    all.addAll(drivers.docs.map((d) => UserModel.fromJson({...d.data(), 'id': d.id, 'role': 'driver'})));
    all.addAll(staff.docs.map((d) => UserModel.fromJson({...d.data(), 'id': d.id, 'role': 'staff'})));
    return all;
  }

  Future<List<UserModel>> getAllStaff() async {
    final snap = await _db.collection('staff').get();
    return snap.docs.map((doc) => UserModel.fromJson({...doc.data(), 'id': doc.id, 'role': 'staff'})).toList();
  }

  Future<void> deleteDriver(String id) async => _db.collection('drivers').doc(id).delete();
  
  Future<void> deleteUser(String id, UserRole role) async {
    String col = role == UserRole.driver ? 'drivers' : (role == UserRole.rider ? 'riders' : 'staff');
    await _db.collection(col).doc(id).delete();
  }

  Future<void> updateDriverEarnings(String id, double amount) async {
    await _db.collection('wallets').doc(id).set({'balance': FieldValue.increment(amount), 'lastUpdated': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<List<Map<String, dynamic>>> getAllTrips({String? driverId, String? riderId}) async {
    try {
      Query query = _db.collection('trips');
      
      // MUHIMU: Ili kuzuia permission-denied, lazima tuwe na filter 
      // inayolingana na Security Rules (riderId au driverId)
      if (driverId != null && driverId.isNotEmpty) {
        query = query.where('driverId', isEqualTo: driverId);
      } else if (riderId != null && riderId.isNotEmpty) {
        query = query.where('riderId', isEqualTo: riderId);
      } else {
        // Ikiwa hakuna ID iliyotolewa, na mtumiaji si Admin, 
        // query hii itakataliwa na Firebase Rules.
        return [];
      }
      
      final snap = await query.get();
      return snap.docs.map((doc) => {...doc.data() as Map<String, dynamic>, 'id': doc.id}).toList();
    } catch (e) {
      debugPrint("❌ DatabaseService.getAllTrips Error: $e");
      rethrow;
    }
  }

  Future<String> getSetting(String key, String def) async {
    final d = await _db.collection('settings').doc(key).get();
    return d.exists ? (d.data()?['value']?.toString() ?? def) : def;
  }

  Future<void> updateSetting(String key, String value) async {
    await _db.collection('settings').doc(key).set({'value': value}, SetOptions(merge: true));
  }

  Stream<List<Map<String, dynamic>>> getPendingTopUps() {
    return _db.collection('payments').where('status', isEqualTo: 'pending').snapshots().map((snap) => snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList());
  }

  Stream<List<Map<String, dynamic>>> getPendingWithdrawals() {
    return _db.collection('withdrawals').where('status', isEqualTo: 'pending').snapshots().map((snap) => snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList());
  }

  Future<void> approveWithdrawal(String withdrawalId, String userId, double amount) async {
    final batch = _db.batch();
    batch.update(_db.collection('withdrawals').doc(withdrawalId), {'status': 'completed', 'processedAt': FieldValue.serverTimestamp()});
    batch.update(_db.collection('wallets').doc(userId), {'balance': FieldValue.increment(-amount), 'lastUpdated': FieldValue.serverTimestamp()});
    batch.set(_db.collection('transactions').doc(), {'driverId': userId, 'amount': -amount, 'type': 'payout', 'description': 'Withdrawal Approved', 'timestamp': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  Future<void> rejectWithdrawal(String id) async {
    await _db.collection('withdrawals').doc(id).update({'status': 'rejected', 'processedAt': FieldValue.serverTimestamp()});
  }

  Future<void> approveTopUp(String paymentId, String userId, double amount) async {
    final batch = _db.batch();
    batch.update(_db.collection('payments').doc(paymentId), {'status': 'completed', 'processedAt': FieldValue.serverTimestamp()});
    batch.set(_db.collection('wallets').doc(userId), {'balance': FieldValue.increment(amount), 'lastUpdated': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    batch.set(_db.collection('transactions').doc(), {'driverId': userId, 'amount': amount, 'type': 'topup', 'description': 'Wallet Top-up Approved', 'timestamp': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  Future<void> approveTopUpDirect(String userId, double amount) async {
    final batch = _db.batch();
    // Record as completed payment immediately
    final payRef = _db.collection('payments').doc();
    batch.set(payRef, {
      'userId': userId,
      'amount': amount,
      'status': 'completed',
      'type': 'topup',
      'processedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    
    batch.set(_db.collection('wallets').doc(userId), {
      'balance': FieldValue.increment(amount), 
      'lastUpdated': FieldValue.serverTimestamp()
    }, SetOptions(merge: true));
    
    batch.set(_db.collection('transactions').doc(), {
      'driverId': userId, 
      'amount': amount, 
      'type': 'topup', 
      'description': 'Wallet Top-up', 
      'timestamp': FieldValue.serverTimestamp()
    });
    await batch.commit();
  }

  Future<void> rejectTopUp(String id) async {
    await _db.collection('payments').doc(id).update({'status': 'rejected', 'processedAt': FieldValue.serverTimestamp()});
  }

  Future<List<String>> getTableNames() async {
    return ['riders', 'drivers', 'staff', 'trips', 'ride_requests', 'wallets', 'transactions', 'payments', 'withdrawals', 'settings', 'it_tickets', 'sos_alerts'];
  }

  Future<List<Map<String, dynamic>>> getTableData(String tableName) async {
    final snap = await _db.collection(tableName).get();
    return snap.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
  }

  Future<void> deleteRecord(String table, String id) async {
    await _db.collection(table).doc(id).delete();
  }

  Future<void> insertOrUpdateRecord(String table, String id, Map<String, dynamic> data) async {
    await _db.collection(table).doc(id).set(data, SetOptions(merge: true));
  }

  Future<void> updateDriverVerification(String id, bool v) async => _db.collection('drivers').doc(id).update({'isVerified': v, 'verificationStatus': v ? 'verified' : 'rejected'});
}
