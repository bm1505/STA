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

  Future<List<Map<String, dynamic>>> getAllTrips({String? driverId, String? riderId}) async {
    if ((driverId == null || driverId.isEmpty) && (riderId == null || riderId.isEmpty)) return [];
    var query = _db.from('trips').select();
    if (driverId != null && driverId.isNotEmpty) query = query.eq('driver_id', driverId);
    if (riderId != null && riderId.isNotEmpty) query = query.eq('rider_id', riderId);
    final rows = await query;
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<String> getSetting(String key, String def) async {
    final row = await _db.from('app_settings').select('value').eq('key', key).maybeSingle();
    return row?['value']?.toString() ?? def;
  }

  Future<void> updateSetting(String key, String value) async {
    await _db.from('app_settings').upsert({'key': key, 'value': value});
  }

  Stream<List<Map<String, dynamic>>> getPendingTopUps() =>
      _db.from('payments').stream(primaryKey: ['id'])
          .map((rows) => rows.where((r) => r['status'] == 'pending')
              .map((r) => Map<String, dynamic>.from(r)).toList());

  Stream<List<Map<String, dynamic>>> getPendingWithdrawals() =>
      _db.from('withdrawal_requests').stream(primaryKey: ['id'])
          .map((rows) => rows.where((r) => r['status'] == 'pending')
              .map((r) => Map<String, dynamic>.from(r)).toList());

  Future<void> approveWithdrawal(String withdrawalId, String userId, double amount) async {
    await _db.rpc('sta_process_withdrawal', params: {
      'p_withdrawal_id': withdrawalId, 'p_user_id': userId, 'p_amount': amount,
      'p_approve': true,
    });
  }

  Future<void> rejectWithdrawal(String id) async {
    await _db.rpc('sta_process_withdrawal', params: {
      'p_withdrawal_id': id, 'p_user_id': _db.auth.currentUser!.id,
      'p_amount': 0, 'p_approve': false,
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
    await _db.from('payments').update({'status': 'failed'}).eq('id', id);
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
