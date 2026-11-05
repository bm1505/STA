import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;
  String _language = 'English';
  ThemeMode _themeMode = ThemeMode.dark;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _profileSubscription;
  bool _isManualLogin = false;

  SupabaseClient get _supabase => Supabase.instance.client;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;
  bool get isManualLogin => _isManualLogin;
  String get language => _language;
  ThemeMode get themeMode => _themeMode;

  AuthProvider() {
    _loadSettings();
    _authSubscription = _supabase.auth.onAuthStateChange.listen((event) {
      final user = event.session?.user ?? _supabase.auth.currentUser;
      if (user == null) {
        _currentUser = null;
        _profileSubscription?.cancel();
        notifyListeners();
      } else if (_currentUser == null) {
        _loadSupabaseProfile(user.id);
      }
    });
  }

  Future<void> checkAuthStatus() async {
    _setLoading(true);
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        await _loadSupabaseProfile(user.id);
      } else {
        _currentUser = null;
      }
    } catch (e) {
      _error = 'Imeshindikana kuthibitisha akaunti: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _loadSupabaseProfile(String userId) async {
    try {
      final row = await _supabase
          .from('profiles')
          .select('user_data, role')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) {
        _currentUser = null;
        return;
      }
      final raw = row['user_data'];
      final data = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      data['id'] = userId;
      data['role'] = row['role'] ?? data['role'] ?? 'rider';
      _currentUser = UserModel.fromJson(data);
      await _saveLocalDisplaySession(_currentUser!);
      _listenToSupabaseProfile(userId);
      notifyListeners();
    } catch (e) {
      _error = 'Imeshindikana kupata taarifa za akaunti: $e';
      notifyListeners();
    }
  }

  void _listenToSupabaseProfile(String userId) {
    _profileSubscription?.cancel();
    _profileSubscription = _supabase
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .listen((rows) {
      if (rows.isEmpty) return;
      final row = rows.first;
      final raw = row['user_data'];
      final data = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      data['id'] = userId;
      data['role'] = row['role'] ?? data['role'] ?? 'rider';
      _currentUser = UserModel.fromJson(data);
      _saveLocalDisplaySession(_currentUser!);
      notifyListeners();
    }, onError: (Object error) {
      debugPrint('STA profile realtime error: $error');
    });
  }

  Future<void> _saveLocalDisplaySession(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', json.encode(user.toJson()));
  }

  Future<void> _saveProfile(UserModel user) async {
    await _supabase.from('profiles').upsert({
      'id': user.id,
      'role': user.role.name,
      'full_name': user.name,
      'email': user.email,
      'phone_number': user.phoneNumber,
      'user_data': user.toJson(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    _currentUser = user;
    await _saveLocalDisplaySession(user);
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _language = prefs.getString('language') ?? 'English';
    _themeMode = (prefs.getBool('isDarkMode') ?? true)
        ? ThemeMode.dark
        : ThemeMode.light;
    notifyListeners();
  }

  Future<void> setLanguage(String lang) async {
    _language = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', lang);
    notifyListeners();
  }

  Future<void> toggleTheme(bool isDark) async {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDark);
    notifyListeners();
  }

  Future<bool> login(String identifier, String password,
      {UserRole? role}) async {
    _error = null;
    _isManualLogin = true;
    _setLoading(true);
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: identifier.trim(),
        password: password,
      );
      if (response.user == null) return false;
      await _loadSupabaseProfile(response.user!.id);
      if (_currentUser == null || (role != null && _currentUser!.role != role)) {
        await logout();
        _error = 'Aina ya akaunti hairuhusiwi hapa.';
        return false;
      }
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      _error = 'Hitilafu ya kuingia: $e';
      return false;
    } finally {
      _isManualLogin = false;
      _setLoading(false);
    }
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    required String phoneNumber,
    required UserRole role,
    String? gender,
    String? dob,
    String? carModel,
    String? carPlate,
    String? carYear,
    String? vehicleType,
  }) async {
    try {
      final newUser = UserModel(
        id: '',
        name: name,
        email: email.trim(),
        phoneNumber: phoneNumber,
        role: role,
        gender: gender,
        dob: dob,
        createdAt: DateTime.now(),
        isVerified: false,
        verificationStatus: role == UserRole.driver
            ? VerificationStatus.pending
            : VerificationStatus.verified,
        carModel: carModel,
        carPlate: carPlate,
        carYear: carYear,
        vehicleType: vehicleType,
      );
      final response = await _supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'role': role.name, 'name': name, 'phone_number': phoneNumber},
      );
      final authUser = response.user;
      if (authUser == null) {
        return {'success': false, 'error': 'Usajili haukukamilika.'};
      }
      final profile = newUser.copyWith();
      final data = profile.toJson()..['id'] = authUser.id;
      if (response.session != null) {
        await _supabase.from('profiles').upsert({
          'id': authUser.id,
          'role': role.name,
          'full_name': name,
          'email': email.trim(),
          'phone_number': phoneNumber,
          'user_data': data,
        });
        await _loadSupabaseProfile(authUser.id);
      }
      return {
        'success': true,
        'userId': authUser.id,
        'requiresEmailConfirmation': response.session == null,
      };
    } on AuthException catch (e) {
      return {'success': false, 'error': e.message};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<bool> updateProfile({
    String? name,
    String? email,
    String? phoneNumber,
    String? gender,
    String? dob,
    String? profileImageUrl,
    bool updatePhotoTimestamp = false,
    String? carModel,
    String? carPlate,
    String? carColor,
    String? carYear,
    String? vehicleType,
    String? licenseUrl,
    String? insuranceUrl,
    String? nationalIdUrl,
    String? vehiclePhotoUrl,
    String? region,
    String? city,
    String? homeAddress,
    String? workAddress,
    String? payoutNumber,
    String? payoutMethod,
  }) async {
    if (_currentUser == null) return false;
    try {
      final updated = _currentUser!.copyWith(
        name: name, email: email, phoneNumber: phoneNumber, gender: gender,
        dob: dob, profileImageUrl: profileImageUrl, carModel: carModel,
        carPlate: carPlate, carColor: carColor, carYear: carYear,
        vehicleType: vehicleType, licenseUrl: licenseUrl,
        insuranceUrl: insuranceUrl, nationalIdUrl: nationalIdUrl,
        vehiclePhotoUrl: vehiclePhotoUrl, region: region, city: city,
        homeAddress: homeAddress, workAddress: workAddress,
        payoutNumber: payoutNumber, payoutMethod: payoutMethod,
        lastPhotoUpdate: updatePhotoTimestamp ? DateTime.now() : null,
      );
      await _saveProfile(updated);
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>> forgotPassword(String identifier) async {
    _setLoading(true);
    try {
      await _supabase.auth.resetPasswordForEmail(identifier.trim());
      return {'success': true, 'message': 'Maelekezo ya kubadili nenosiri yametumwa.'};
    } on AuthException catch (e) {
      return {'success': false, 'error': e.message};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    } finally {
      _setLoading(false);
    }
  }

  Future<Map<String, dynamic>> resetPassword(
      String identifier, String otp, String newPassword) async {
    _setLoading(true);
    try {
      await _supabase.auth.verifyOTP(
        email: identifier.trim(),
        token: otp,
        type: OtpType.recovery,
      );
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
      return {'success': true, 'message': 'Nenosiri limebadilishwa.'};
    } on AuthException catch (e) {
      return {'success': false, 'error': e.message};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> verifyOtp(String identifier, String otp) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        email: identifier.trim(), token: otp, type: OtpType.email,
      );
      if (response.user != null) await _loadSupabaseProfile(response.user!.id);
      return response.user != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resendOtp(String identifier) async {
    try {
      await _supabase.auth.resend(
        type: OtpType.signup, email: identifier.trim(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<UserModel>> getPendingDrivers() async {
    try {
      final rows = await _supabase.from('profiles')
          .select('id, role, user_data')
          .eq('role', 'driver');
      return rows.map((row) {
        final data = row['user_data'] is Map
            ? Map<String, dynamic>.from(row['user_data'])
            : <String, dynamic>{};
        data['id'] = row['id'];
        data['role'] = row['role'];
        return UserModel.fromJson(data);
      }).where((user) => !user.isVerified ||
          user.profileEditStatus == 'submitted').toList();
    } catch (e) {
      debugPrint('Unable to load pending drivers from Supabase: $e');
      return [];
    }
  }

  Future<void> logout() async {
    await _profileSubscription?.cancel();
    await _supabase.auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_data');
    _currentUser = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>> signInWithGoogle(UserRole role) async {
    _setLoading(true);
    _error = null;
    try {
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.sta://login-callback/',
        queryParams: {'prompt': 'select_account'},
      );
      return {'success': true, 'message': 'Endelea na uthibitishaji wa Google.'};
    } on AuthException catch (e) {
      _error = e.message;
      return {'success': false, 'error': e.message};
    } catch (e) {
      _error = e.toString();
      return {'success': false, 'error': _error};
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _profileSubscription?.cancel();
    super.dispose();
  }
}
