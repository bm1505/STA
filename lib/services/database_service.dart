import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user.dart';
import 'otp_service.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  DatabaseService._();

  SupabaseClient get _db => Supabase.instance.client;
  final String _uploadcarePubKey = '70eabc59a303435eb281';

  bool isMasterAdmin(String email) =>
      email.toLowerCase() == 'admin@sta.co.tz' ||
      email.toLowerCase() == 'mahega@sta.co.tz';

  Future<UserModel?> getUser(String id, {UserRole? expectedRole}) async {
    try {
      final row = await _db.from('profiles')
          .select('id, role, user_data, email')
          .or('id.eq.$id,email.eq.$id')
          .maybeSingle();
      if (row == null) return null;
      final data = row['user_data'] is Map
          ? Map<String, dynamic>.from(row['user_data'])
          : <String, dynamic>{};
      data['id'] = row['id'];
      data['role'] = row['role'];
      data['email'] = row['email'] ?? data['email'] ?? '';
      final user = UserModel.fromJson(data);
      if (expectedRole != null && user.role != expectedRole) return null;
      return user;
    } catch (e) {
      debugPrint('Supabase getUser failed: $e');
      return null;
    }
  }

  Future<void> saveUser(UserModel user) async {
    await _db.from('profiles').upsert({
      'id': user.id,
      'role': user.role.name,
      'full_name': user.name,
      'email': user.email,
      'phone_number': user.phoneNumber,
      'user_data': user.toJson(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<bool> sendEmailOTP(String email, {String name = 'User'}) async {
    try {
      await _db.auth.signInWithOtp(email: email.trim(), emailRedirectTo: null);
      return true;
    } catch (e) {
      debugPrint('Supabase OTP send failed: $e');
      return false;
    }
  }

  Future<bool> verifyEmailOTP(String email, String otp) async {
    try {
      final result = await _db.auth.verifyOTP(
        email: email.trim(), token: otp, type: OtpType.email,
      );
      return result.user != null;
    } catch (e) {
      debugPrint('Supabase OTP verification failed: $e');
      return false;
    }
  }

  Future<void> incrementDriverRides(String driverId) async {
    await _db.rpc('sta_increment_driver_rides', params: {'p_driver_id': driverId});
  }

  Future<String> uploadDriverDocument(String userId, String type, dynamic file) =>
      _uploadDocInternal(userId, type, file);

  Future<String> _uploadDocInternal(String userId, String type, dynamic file) async {
    try {
      Uint8List? bytes;
      if (file is Uint8List) {
        bytes = file;
      } else if (file is File) {
        bytes = await file.readAsBytes();
      } else if (file is String && !file.startsWith('http')) {
        bytes = await File(file).readAsBytes();
      }
      if (bytes == null) return '';
      final extension = type.toLowerCase().contains('pdf') ? 'pdf' : 'jpg';
      final path = '$userId/${type.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      await _db.storage.from('driver-documents').uploadBinary(
        path, bytes,
        fileOptions: const FileOptions(upsert: true),
      );
      final url = _db.storage.from('driver-documents').getPublicUrl(path);
      final field = _profileField(type);
      if (field != null) {
        final profile = await _db.from('profiles')
            .select('user_data').eq('id', userId).maybeSingle();
        final data = profile?['user_data'] is Map
            ? Map<String, dynamic>.from(profile!['user_data'])
            : <String, dynamic>{};
        data[field] = url;
        await _db.from('profiles').update({'user_data': data}).eq('id', userId);
      }
      return url;
    } catch (e) {
      debugPrint('Supabase document upload failed: $e');
      return '';
    }
  }

  String? _profileField(String type) {
    final t = type.toLowerCase();
    if (t.contains('license')) return 'licenseUrl';
    if (t.contains('insurance')) return 'insuranceUrl';
    if (t.contains('national') || t.contains('nida')) return 'nationalIdUrl';
    if (t.contains('vehicle')) return 'vehiclePhotoUrl';
    if (t.contains('profile')) return 'profileImageUrl';
    return null;
  }

  Future<void> updateAnyUserProfilePic(String userId, String url) async {
    final row = await _db.from('profiles').select('user_data')
        .eq('id', userId).maybeSingle();
    if (row == null) return;
    final data = row['user_data'] is Map
        ? Map<String, dynamic>.from(row['user_data'])
        : <String, dynamic>{};
    data['profileImageUrl'] = url;
    await _db.from('profiles').update({'user_data': data}).eq('id', userId);
  }

  Future<void> updateDriverVerificationStatus(
    String id, dynamic status, {String? reason, bool isUpdate = false}
  ) async {
    final statusStr = status is VerificationStatus
        ? status.name : status.toString();
    final row = await _db.from('profiles').select('user_data')
        .eq('id', id).maybeSingle();
    if (row == null) return;
    final data = row['user_data'] is Map
        ? Map<String, dynamic>.from(row['user_data'])
        : <String, dynamic>{};
    if (isUpdate) {
      if (statusStr == 'verified' && data['pendingUpdates'] is Map) {
        data.addAll(Map<String, dynamic>.from(data['pendingUpdates']));
      }
      data.remove('pendingUpdates');
      data['profileEditStatus'] = 'none';
    } else {
      data['verificationStatus'] = statusStr;
      data['isVerified'] = statusStr == 'verified';
    }
    if (reason != null) data['rejectionReason'] = reason;
    await _db.from('profiles').update({'user_data': data}).eq('id', id);
    await _db.from('driver_profiles').upsert({
      'user_id': id, 'verification_status': statusStr,
    });
  }

  Future<void> recordTrip(Map<String, dynamic> tripData) async {
    await _db.rpc('sta_record_trip', params: {'p_trip_data': tripData});
  }

  Stream<Map<String, dynamic>?> getWalletStream(String userId) =>
      _db.from('wallets').stream(primaryKey: ['user_id'])
          .eq('user_id', userId)
          .map((rows) => rows.isEmpty ? null : Map<String, dynamic>.from(rows.first));

  Stream<List<Map<String, dynamic>>> getTransactionsStream(String userId) =>
      _db.from('wallet_transactions').stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .map((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());

  Stream<List<Map<String, dynamic>>> getPendingRequestsStream(String userId) =>
      _db.from('payments').stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .map((rows) => rows.where((r) => r['status'] == 'pending')
              .map((r) => {...Map<String, dynamic>.from(r), 'type': 'topup', 'isPending': true})
              .toList());

  Stream<List<UserModel>> getDriversStream() =>
      _db.from('profiles').stream(primaryKey: ['id']).eq('role', 'driver')
          .map((rows) => rows.map(_userFromRow).toList());

  UserModel _userFromRow(Map<String, dynamic> row) {
    final data = row['user_data'] is Map
        ? Map<String, dynamic>.from(row['user_data'])
        : <String, dynamic>{};
    data['id'] = row['id'];
    data['role'] = row['role'];
    data['email'] = row['email'] ?? data['email'] ?? '';
    return UserModel.fromJson(data);
  }

  Future<List<UserModel>> getAllDrivers() async {
    final rows = await _db.from('profiles').select().eq('role', 'driver');
    return rows.map(_userFromRow).toList();
  }

  Future<List<UserModel>> getAllUsers() async {
    final rows = await _db.from('profiles').select();
    return rows.map(_userFromRow).toList();
  }

  Future<List<UserModel>> getAllStaff() async {
    final rows = await _db.from('profiles').select().eq('role', 'staff');
    return rows.map(_userFromRow).toList();
  }

  Future<void> deleteDriver(String id) async =>
      _db.from('profiles').delete().eq('id', id);

  Future<void> deleteUser(String id, UserRole role) async =>
      _db.from('profiles').delete().eq('id', id).eq('role', role.name);

  Future<void> updateDriverEarnings(String id, double amount) async {
    await _db.rpc('sta_adjust_wallet', params: {
      'p_user_id': id, 'p_amount': amount, 'p_type': 'manual_adjustment',
    });
  }

  Future<List<Map<String, dynamic>>> getAllTrips({
    String? driverId,
    String? riderId,
    bool adminView = false,
  }) async {
    if ((driverId == null || driverId.isEmpty) &&
        (riderId == null || riderId.isEmpty) && !adminView) return [];
    var query = _db.from('trips').select();
    if (driverId != null && driverId.isNotEmpty) query = query.eq('driver_id', driverId);
    if (riderId != null && riderId.isNotEmpty) query = query.eq('rider_id', riderId);
    final rows = await query.order('created_at', ascending: false);
    return _enrichTripRows(rows.map((r) => Map<String, dynamic>.from(r)).toList());
  }

  Stream<List<Map<String, dynamic>>> getDriverTripsStream(String driverId) =>
      _db.from('trips').stream(primaryKey: ['id'])
          .eq('driver_id', driverId)
          .asyncMap((rows) => _enrichTripRows(rows.map((r) => Map<String, dynamic>.from(r)).toList()));

  Stream<List<Map<String, dynamic>>> getAdminTripsStream() =>
      _db.from('trips').stream(primaryKey: ['id'])
          .asyncMap((rows) => _enrichTripRows(rows.map((r) => Map<String, dynamic>.from(r)).toList()));

  Future<List<Map<String, dynamic>>> _enrichTripRows(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return rows;
    final rideIds = rows.map((r) => r['ride_request_id']?.toString())
        .whereType<String>().where((id) => id.isNotEmpty).toSet().toList();
    final ridesById = <String, Map<String, dynamic>>{};
    if (rideIds.isNotEmpty) {
      final rides = await _db.from('ride_requests')
          .select('id,pickup_label,dropoff_label,vehicle_type,ride_data,payment_status,estimated_fare,final_fare')
          .inFilter('id', rideIds);
      for (final ride in rides) {
        ridesById[ride['id'].toString()] = Map<String, dynamic>.from(ride);
      }
    }
    return rows.map((trip) {
      final ride = ridesById[trip['ride_request_id']?.toString()] ?? <String, dynamic>{};
      final rideData = ride['ride_data'] is Map
          ? Map<String, dynamic>.from(ride['ride_data'] as Map)
          : <String, dynamic>{};
      final completedAt = trip['completed_at'] ?? trip['created_at'];
      return {
        ...trip,
        'timestamp': completedAt,
        'pickupAddress': ride['pickup_label'] ?? 'Unknown Location',
        'dropoffAddress': ride['dropoff_label'] ?? 'Unknown Destination',
        'pickup': ride['pickup_label'],
        'dropoff': ride['dropoff_label'],
        'vehicleType': ride['vehicle_type'],
        'paymentStatus': ride['payment_status'],
        'fare': trip['fare'] ?? ride['final_fare'] ?? ride['estimated_fare'] ?? 0,
        'distance': ((trip['distance_meters'] as num?)?.toDouble() ?? 0) / 1000,
        'duration': (((trip['duration_seconds'] as num?)?.toDouble() ?? 0) / 60).round(),
        'riderName': rideData['riderName'] ?? '',
        'driverName': rideData['driverName'] ?? '',
        'riderId': trip['rider_id'],
        'driverId': trip['driver_id'],
      };
    }).toList();
  }

  Stream<List<UserModel>> getAdminProfilesStream() =>
      _db.from('profiles').stream(primaryKey: ['id'])
          .map((rows) => rows.map(_userFromRow).toList());
  Stream<Map<String, dynamic>> getAdminStatsStream() =>
      _db.from('trips').stream(primaryKey: ['id']).asyncMap((tripRows) async {
        final profiles = await _db.from('profiles').select('id,role');
        final activeRides = await _db.from('ride_requests').select('id')
            .inFilter('status', ['accepted', 'driver_arrived', 'in_progress']);
        final commissions = await _db.from('wallet_transactions')
            .select('amount,created_at')
            .eq('transaction_type', 'commission_deduction')
            .eq('status', 'completed');
        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        double totalFare = 0;
        double todayFare = 0;
        for (final trip in tripRows) {
          final fare = (trip['fare'] as num?)?.toDouble() ?? 0;
          totalFare += fare;
          final created = DateTime.tryParse(
              (trip['completed_at'] ?? trip['created_at'] ?? '').toString());
          if (created != null && created.isAfter(startOfToday)) todayFare += fare;
        }
        double totalCommission = 0;
        double todayCommission = 0;
        for (final row in commissions) {
          final amount = (row['amount'] as num?)?.toDouble() ?? 0;
          totalCommission += amount;
          final created = DateTime.tryParse(row['created_at']?.toString() ?? '');
          if (created != null && created.isAfter(startOfToday)) todayCommission += amount;
        }
        return {
          'drivers': profiles.where((p) => p['role'] == 'driver').length,
          'riders': profiles.where((p) => p['role'] == 'rider').length,
          'totalTrips': tripRows.length,
          'activeTrips': activeRides.length,
          'totalFare': totalFare,
          'todayFare': todayFare,
          'totalCommissions': totalCommission,
          'todayCommissions': todayCommission,
        };
      });

  Stream<List<UserModel>> getAdminRecentUsersStream() =>
      getAdminProfilesStream().map((users) {
        users.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return users.take(8).toList();
      });

  Stream<List<UserModel>> getPendingDriversStream() =>
      getDriversStream().map((drivers) => drivers
          .where((driver) => driver.verificationStatus == VerificationStatus.pending)
          .toList());

  Stream<List<Map<String, dynamic>>> getTopDriversStream() =>
      _db.from('driver_profiles').stream(primaryKey: ['user_id']).asyncMap((rows) async {
        final sorted = rows.toList()
          ..sort((a, b) => ((b['total_rides'] as num?)?.toInt() ?? 0)
              .compareTo((a['total_rides'] as num?)?.toInt() ?? 0));
        final ids = sorted.take(10).map((r) => r['user_id'].toString()).toList();
        if (ids.isEmpty) return <Map<String, dynamic>>[];
        final profiles = await _db.from('profiles')
            .select('id,user_data,full_name').inFilter('id', ids);
        final byId = {for (final p in profiles) p['id'].toString(): p};
        return sorted.take(10).map((driver) {
          final profile = byId[driver['user_id'].toString()];
          final data = profile?['user_data'] is Map
              ? Map<String, dynamic>.from(profile!['user_data'] as Map)
              : <String, dynamic>{};
          return {
            ...driver,
            'id': driver['user_id'],
            'name': data['name'] ?? profile?['full_name'] ?? 'Driver',
            'totalRides': driver['total_rides'] ?? 0,
          };
        }).toList();
      });

  Stream<List<Map<String, dynamic>>> getCommissionTransactionsStream() =>
      _db.from('wallet_transactions').stream(primaryKey: ['id'])
          .eq('transaction_type', 'commission_deduction')
          .map((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());


  Stream<List<Map<String, dynamic>>> getDriverRatingsStream(String driverId) =>
      _db.from('ride_ratings').stream(primaryKey: ['id'])
          .eq('driver_id', driverId)
          .map((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());

  Future<void> allowDriverProfileEdit(String driverId) async {
    final row = await _db.from('profiles').select('user_data')
        .eq('id', driverId).single();
    final data = row['user_data'] is Map
        ? Map<String, dynamic>.from(row['user_data'])
        : <String, dynamic>{};
    data['profileEditStatus'] = 'allowed';
    await _db.from('profiles').update({'user_data': data}).eq('id', driverId);
  }

  Stream<List<Map<String, dynamic>>> getAdminTableStream(String tableName) {
    const primaryKeys = {
      'profiles': ['id'],
      'driver_profiles': ['user_id'],
      'driver_locations': ['driver_id'],
      'ride_requests': ['id'],
      'trips': ['id'],
      'wallets': ['user_id'],
      'wallet_transactions': ['id'],
      'payments': ['id'],
      'withdrawal_requests': ['id'],
      'notification_broadcasts': ['id'],
      'app_settings': ['key'],
      'chat_messages': ['id'],
      'sos_alerts': ['id'],
      'ride_ratings': ['id'],
    };
    final keys = primaryKeys[tableName];
    if (keys == null) throw ArgumentError('Table is not available in the STA admin explorer');
    return _db.from(tableName).stream(primaryKey: keys)
        .map((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());
  }

  Future<String> getSetting(String key, String def) async {
    final row = await _db.from('app_settings').select('value').eq('key', key).maybeSingle();
    return row?['value']?.toString() ?? def;
  }

  Future<void> updateSetting(String key, String value) async {
    await _db.from('app_settings').upsert({'key': key, 'value': value});
  }

  Stream<List<Map<String, dynamic>>> getAllWalletsStream() =>
      _db.from('wallets').stream(primaryKey: ['user_id'])
          .map((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());

  Stream<List<Map<String, dynamic>>> getPendingTopUps() =>
      _db.from('payments').stream(primaryKey: ['id'])
          .map((rows) => rows.where((r) => r['status'] == 'pending' &&
              (r['provider_payload'] is Map
                ? (r['provider_payload'] as Map)['type'] == 'topup'
                : false))
              .map((r) => {
                ...Map<String, dynamic>.from(r),
                'userId': r['user_id'],
                'phoneNumber': r['phone_number'] ?? 'N/A',
              }).toList());

  Stream<List<Map<String, dynamic>>> getPendingWithdrawals() =>
      _db.from('withdrawal_requests').stream(primaryKey: ['id'])
          .map((rows) => rows.where((r) => r['status'] == 'pending')
              .map((r) => {
                ...Map<String, dynamic>.from(r),
                'userId': r['user_id'],
                'phoneNumber': r['phone_number'] ?? '',
              }).toList());

  Future<String> requestWithdrawal({
    required double amount,
    required String phoneNumber,
    required String payoutMethod,
    required String payoutProvider,
  }) async {
    final result = await _db.rpc('sta_request_withdrawal', params: {
      'p_amount': amount,
      'p_phone_number': phoneNumber,
      'p_payout_method': payoutMethod,
      'p_payout_provider': payoutProvider,
    });
    return result.toString();
  }

  Future<void> approveWithdrawal(String withdrawalId, String userId, double amount) async {
    await _db.rpc('sta_process_withdrawal', params: {
      'p_withdrawal_id': withdrawalId, 'p_user_id': userId, 'p_amount': amount,
      'p_approve': true,
    });
  }

  Future<void> rejectWithdrawal(String id) async {
    final request = await _db.from('withdrawal_requests')
        .select('user_id').eq('id', id).single();
    await _db.rpc('sta_process_withdrawal', params: {
      'p_withdrawal_id': id,
      'p_user_id': request['user_id'],
      'p_amount': 0,
      'p_approve': false,
    });
  }

  Future<void> approveTopUp(String paymentId, String userId, double amount) async {
    await _db.rpc('sta_process_topup', params: {
      'p_payment_id': paymentId, 'p_user_id': userId, 'p_amount': amount,
    });
  }

  Future<void> approveTopUpDirect(String userId, double amount) async {
    await _db.rpc('sta_manual_topup', params: {
      'p_user_id': userId, 'p_amount': amount,
    });
  }

  Future<void> rejectTopUp(String id) async {
    await _db.rpc('sta_reject_payment', params: {'p_payment_id': id});
  }

  Future<List<String>> getTableNames() async => [
    'profiles', 'driver_profiles', 'driver_locations', 'ride_requests',
    'trips', 'wallets', 'wallet_transactions', 'payments',
    'withdrawal_requests', 'notification_broadcasts', 'app_settings',
    'chat_messages', 'sos_alerts',
  ];

  Future<List<Map<String, dynamic>>> getTableData(String tableName) async {
    const allowed = {
      'profiles', 'driver_profiles', 'driver_locations', 'ride_requests',
      'trips', 'wallets', 'wallet_transactions', 'payments',
      'withdrawal_requests', 'notification_broadcasts', 'app_settings',
      'chat_messages', 'sos_alerts',
    };
    if (!allowed.contains(tableName)) throw ArgumentError('Unknown table');
    final rows = await _db.from(tableName).select();
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<void> deleteRecord(String table, String id) async {
    const allowed = {'notification_broadcasts', 'app_settings'};
    if (!allowed.contains(table)) throw ArgumentError('Operation not allowed');
    await _db.from(table).delete().eq('id', id);
  }

  Future<void> insertOrUpdateRecord(String table, String id, Map<String, dynamic> data) async {
    const allowed = {'app_settings'};
    if (!allowed.contains(table)) throw ArgumentError('Operation not allowed');
    await _db.from(table).upsert({...data, 'id': id});
  }

  Future<void> updateDriverVerification(String id, bool verified) async {
    await updateDriverVerificationStatus(
      id, verified ? VerificationStatus.verified : VerificationStatus.rejected,
    );
  }
}
