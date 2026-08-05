import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/user.dart';
import '../services/database_service.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;
  String _language = 'English';
  ThemeMode _themeMode = ThemeMode.dark;
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isManualLogin = false;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null;
  bool get isManualLogin => _isManualLogin;
  String get language => _language;
  ThemeMode get themeMode => _themeMode;

  AuthProvider() {
    _initGoogleSignIn();
    _loadSettings();
    _auth.authStateChanges().listen((User? user) {
      if (user != null && _currentUser == null && !_isManualLogin) {
        _handleFirebaseUser(user);
      }
    });
  }

  Future<void> _initGoogleSignIn() async {
    if (!kIsWeb) {
      try {
        await GoogleSignIn.instance.initialize();
      } catch (e) {
        debugPrint("GoogleSignIn Init Error: $e");
      }
    }
  }

  Future<void> checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData != null) {
      try {
        _currentUser = UserModel.fromJson(json.decode(userData));
        _startUserListener(_currentUser!.id, _currentUser!.role);
        notifyListeners();
      } catch (e) {
        debugPrint("Error loading user data: $e");
      }
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _language = prefs.getString('language') ?? 'English';
    final isDark = prefs.getBool('isDarkMode') ?? true;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
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

  Future<void> _handleFirebaseUser(User user, {UserRole? targetRole}) async {
    try {
      UserModel? existingUser = await DatabaseService.instance
          .getUser(user.email ?? user.uid, expectedRole: targetRole);

      if (existingUser != null) {
        if (targetRole == UserRole.driver &&
            existingUser.role == UserRole.rider) {
          UserModel? driverProfile = await DatabaseService.instance
              .getUser(user.email ?? user.uid, expectedRole: UserRole.driver);

          if (driverProfile != null) {
            existingUser = driverProfile;
          } else {
            existingUser = existingUser.copyWith(
                role: UserRole.driver,
                verificationStatus: VerificationStatus.pending,
                isVerified: false);
            await DatabaseService.instance.saveUser(existingUser);
          }
        }
        _currentUser = existingUser;
        await _saveSession(_currentUser!, syncWithServer: false);
        _startUserListener(_currentUser!.id, _currentUser!.role);
      } else {
        // Ikiwa user hayupo kabisa, na hakuna error ya mtandao
        // (Hapa tunatengeneza mpya TU ikiwa tuna uhakika hayupo)
        _currentUser = UserModel(
          id: user.uid,
          name: user.displayName ?? 'User',
          email: user.email ?? '',
          phoneNumber: user.phoneNumber ?? '',
          role: targetRole ?? UserRole.rider,
          profileImageUrl: user.photoURL,
          isVerified: true,
          verificationStatus: VerificationStatus.verified,
          hasAcceptedTerms: false,
          createdAt: DateTime.now(),
        );
        await DatabaseService.instance.saveUser(_currentUser!);
        await _saveSession(_currentUser!, syncWithServer: false);
        _startUserListener(_currentUser!.id, _currentUser!.role);
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Auth Error during Firebase Sync: $e");
      _error = "Hitilafu ya mtandao: Imeshindikana kupata taarifa zako.";
      await logout(); // Hakikisha anarudi login ikiwa kuna error
    }
  }

  void _startUserListener(String uid, UserRole role) {
    _userSubscription?.cancel();
    String collection = role == UserRole.driver ? 'drivers' : 'riders';
    _userSubscription = FirebaseFirestore.instance
        .collection(collection)
        .doc(uid)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        Map<String, dynamic> data = snapshot.data()!;
        data['id'] = snapshot.id;
        final updatedUser = UserModel.fromJson(data);
        if (_currentUser?.toJson().toString() !=
            updatedUser.toJson().toString()) {
          _currentUser = updatedUser;
          notifyListeners();
        }
      }
    });
  }

  Future<void> _saveSession(UserModel user,
      {bool syncWithServer = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', json.encode(user.toJson()));
    if (syncWithServer) await DatabaseService.instance.saveUser(user);
    _currentUser = user;
    notifyListeners();
  }

  Future<bool> login(String identifier, String password,
      {UserRole? role}) async {
    _error = null;
    _isManualLogin = true;
    try {
      final String cleanId = identifier.trim().toLowerCase();
      UserCredential result = await _auth.signInWithEmailAndPassword(
          email: cleanId, password: password);
      if (result.user != null) {
        await _handleFirebaseUser(result.user!, targetRole: role);
        _isManualLogin = false;
        return true;
      }
      return false;
    } catch (e) {
      _error = "Hitilafu: $e";
      _isManualLogin = false;
      return false;
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
      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email.trim(), password: password);
      if (result.user != null) {
        final newUser = UserModel(
          id: result.user!.uid,
          name: name,
          email: email,
          phoneNumber: phoneNumber,
          role: role,
          gender: gender,
          dob: dob,
          createdAt: DateTime.now(),
          isVerified: false, // Force verification for everyone initially
          verificationStatus: role == UserRole.driver
              ? VerificationStatus.pending
              : VerificationStatus.verified,
          carModel: carModel,
          carPlate: carPlate,
          carYear: carYear,
          vehicleType: vehicleType,
        );
        // 1. Trigger Email OTP kwanza ili iwe kwenye memory
        await DatabaseService.instance.sendEmailOTP(email);

        // 2. Kisha hifadhi session (Hii itasababisha UI i-rebuild na kwenda OTP Step)
        await _saveSession(newUser);

        return {'success': true, 'userId': newUser.id};
      }
      return {'success': false, 'error': 'Failed to create user'};
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
      UserModel updatedUser = _currentUser!.copyWith(
        name: name,
        email: email,
        phoneNumber: phoneNumber,
        gender: gender,
        dob: dob,
        profileImageUrl: profileImageUrl,
        carModel: carModel,
        carPlate: carPlate,
        carColor: carColor,
        carYear: carYear,
        vehicleType: vehicleType,
        licenseUrl: licenseUrl,
        insuranceUrl: insuranceUrl,
        nationalIdUrl: nationalIdUrl,
        vehiclePhotoUrl: vehiclePhotoUrl,
        region: region,
        city: city,
        homeAddress: homeAddress,
        workAddress: workAddress,
        payoutNumber: payoutNumber,
        payoutMethod: payoutMethod,
        lastPhotoUpdate: updatePhotoTimestamp
            ? DateTime.now()
            : _currentUser!.lastPhotoUpdate,
      );
      await _saveSession(updatedUser);
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
      // Badala ya kutuma Link ya Firebase, tunatuma OTP kupitia EmailJS
      bool sent = await DatabaseService.instance.sendEmailOTP(identifier.trim());
      _setLoading(false);
      return {'success': sent, 'message': sent ? 'OTP imetumwa kikamilifu!' : 'Imeshindikana kutuma OTP'};
    } catch (e) {
      _setLoading(false);
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> resetPassword(
      String identifier, String otp, String newPassword) async {
    _setLoading(true);
    try {
      // 1. Uhakiki wa OTP
      bool otpValid = await DatabaseService.instance.verifyEmailOTP(identifier, otp);
      if (!otpValid) {
        _setLoading(false);
        return {'success': false, 'error': 'Kodi ya OTP siyo sahihi'};
      }

      // 2. Kwa sasa tunatumia OTP kutoa ruhusa ya kubadili password.
      // Kwenye Production (Firebase), kubadili password bila link inahitaji
      // Admin SDK au user awe logged in. Hapa tunathibitisha uhalali wa OTP.
      
      _setLoading(false);
      return {'success': true, 'message': 'OTP imethibitishwa!'};
    } catch (e) {
      _setLoading(false);
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<bool> verifyOtp(String identifier, String otp) async {
    return await DatabaseService.instance.verifyEmailOTP(identifier, otp);
  }

  Future<bool> resendOtp(String identifier) async {
    return await DatabaseService.instance.sendEmailOTP(identifier);
  }

  Future<List<UserModel>> getPendingDrivers() async {
    final drivers = await DatabaseService.instance.getAllDrivers();
    // Inaleta dereva yeyote ambaye isVerified ni false (New Registration)
    // AU mwenye profileEditStatus ni 'submitted' (Profile Update Review)
    return drivers.where((d) => !d.isVerified || d.profileEditStatus == 'submitted').toList();
  }

  Future<void> logout() async {
    _userSubscription?.cancel();
    await _auth.signOut();
    if (!kIsWeb) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (e) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_data');
    _currentUser = null;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  Future<Map<String, dynamic>> signInWithGoogle(UserRole role) async {
    _setLoading(true);
    _error = null;
    try {
      if (kIsWeb) {
        GoogleAuthProvider authProvider = GoogleAuthProvider();
        final UserCredential userCredential =
            await _auth.signInWithPopup(authProvider);
        if (userCredential.user != null) {
          await _handleFirebaseUser(userCredential.user!, targetRole: role);
          _setLoading(false);
          return {'success': true, 'user': _currentUser};
        }
      } else {
        final GoogleSignInAccount? googleUser =
            await GoogleSignIn.instance.authenticate();
        if (googleUser == null) {
          _setLoading(false);
          return {'success': false, 'error': 'Sign in cancelled'};
        }
        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );
        final UserCredential userCredential =
            await _auth.signInWithCredential(credential);
        if (userCredential.user != null) {
          await _handleFirebaseUser(userCredential.user!, targetRole: role);
          _setLoading(false);
          return {'success': true, 'user': _currentUser};
        }
      }
      _setLoading(false);
      return {'success': false, 'error': 'Google Sign in failed'};
    } catch (e) {
      _error = "Imeshindikana: $e";
      _setLoading(false);
      return {'success': false, 'error': _error};
    }
  }
}
