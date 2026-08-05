import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'dart:typed_data';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../utils/theme.dart';
import '../services/database_service.dart';
import '../services/localization_service.dart';
import '../services/otp_service.dart';

class DriverRegistrationFlow extends StatefulWidget {
  const DriverRegistrationFlow({super.key});

  @override
  State<DriverRegistrationFlow> createState() => _DriverRegistrationFlowState();
}

class _DriverRegistrationFlowState extends State<DriverRegistrationFlow> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isLoading = false;

  // Step 0: Account
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  // Step 1: OTP
  final _otpController = TextEditingController();

  // Step 2: Personal
  String? _selectedGender;
  String? _selectedRegion;
  final _cityController = TextEditingController();

  // Step 3: Vehicle
  final _carModelController = TextEditingController();
  final _plateNumberController = TextEditingController();
  final _colorController = TextEditingController();
  final _yearController = TextEditingController();
  String? _selectedVehicleType;
  File? _vehiclePhoto;
  Uint8List? _vehiclePhotoWeb;

  // Step 4: Documents
  File? _licensePhoto;
  Uint8List? _licensePhotoWeb;
  File? _insurancePhoto;
  Uint8List? _insurancePhotoWeb;
  File? _idPhoto;
  Uint8List? _idPhotoWeb;
  File? _profilePhoto;
  Uint8List? _profilePhotoWeb;

  @override
  void initState() {
    super.initState();
    // Angalia kama tayari tuna user ambaye hajamaliza registration
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final user = auth.currentUser;
      
      if (auth.isAuthenticated && user?.role == UserRole.driver) {
        int resumeStep = 0;
        
        // Jaza data ambazo tayari tunazo
        _emailController.text = user?.email ?? "";
        _nameController.text = user?.name ?? "";
        _phoneController.text = user?.phoneNumber ?? "";
        
        // Tambua step ya kuendelea nayo
        if (user!.isVerified) {
          if (user.carModel != null && user.carModel!.isNotEmpty) {
            if (user.licenseUrl != null && user.licenseUrl!.isNotEmpty) {
              resumeStep = 5; // Review
            } else {
              resumeStep = 4; // Documents
            }
          } else if (user.gender != null) {
            resumeStep = 3; // Vehicle
          } else {
            resumeStep = 2; // Personal
          }
        } else {
          resumeStep = 1; // OTP
        }

        if (resumeStep > 0) {
          debugPrint("Resuming registration at step $resumeStep");
          _goToPage(resumeStep);
        }
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    _cityController.dispose();
    _carModelController.dispose();
    _plateNumberController.dispose();
    _colorController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _nextStep() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final lang = auth.language;

    if (_currentStep == 0) {
      // Create Account & Send OTP
      if (_emailController.text.isEmpty ||
          _passwordController.text.length < 6) {
        _showError(LocalizationService.translate('fill_email_pass_err', lang));
        return;
      }

      setState(() => _isLoading = true);
      try {
        // Hapa tunatengeneza account kwanza
        debugPrint("Starting registration for ${_emailController.text.trim()}");
        final res = await auth.register(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          name: _nameController.text.trim(),
          phoneNumber: _phoneController.text.trim(),
          role: UserRole.driver,
        );

        if (res['success'] == true) {
          debugPrint("Usajili umefanikiwa, kodi inatumwa...");
          
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(LocalizationService.translate('otp_sent_msg', lang).replaceFirst('{email}', _emailController.text.trim())),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          _goToPage(1);
        } else {
          debugPrint("Registration failed: ${res['error']}");
          _showError(res['error'] ??
              LocalizationService.translate('registration_failed', lang));
        }
      } catch (e) {
        debugPrint("Exception during registration: $e");
        _showError(
            "${LocalizationService.translate('error_occurred', lang).replaceFirst('{error}', '')}: $e");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else if (_currentStep == 1) {
      // Verify OTP
      setState(() => _isLoading = true);
      try {
        bool verified = await DatabaseService.instance.verifyEmailOTP(
            _emailController.text.trim(), _otpController.text.trim());

        if (verified) {
          _goToPage(2);
        } else {
          _showError(LocalizationService.translate('otp_invalid', lang));
        }
      } catch (e) {
        _showError("Hitilafu ya uhakiki: $e");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else if (_currentStep == 2) {
      // Personal Info (Already in memory, just move)
      if (_selectedGender == null || _selectedRegion == null) {
        _showError(LocalizationService.translate('select_gender_region', lang));
        return;
      }
      _goToPage(3);
    } else if (_currentStep == 3) {
      // Vehicle Info
      if (_carModelController.text.isEmpty ||
          _plateNumberController.text.isEmpty) {
        _showError(LocalizationService.translate('fill_vehicle_info', lang));
        return;
      }
      _goToPage(4);
    } else if (_currentStep == 4) {
      // Documents
      if ((kIsWeb && (_licensePhotoWeb == null || _profilePhotoWeb == null)) ||
          (!kIsWeb && (_licensePhoto == null || _profilePhoto == null))) {
        _showError(LocalizationService.translate('docs_required', lang));
        return;
      }
      _goToPage(5);
    }
  }

  void _goToPage(int index) {
    _pageController.animateToPage(index,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    setState(() => _currentStep = index);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final lang = auth.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.backgroundCharcoal : Colors.white,
      appBar: AppBar(
        title: Text(
            "${LocalizationService.translate('driver_registration', lang)} (${_currentStep + 1}/6)",
            style: TextStyle(
                fontSize: 16, color: isDark ? Colors.white : Colors.black)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _currentStep > 0
            ? IconButton(
                icon: Icon(Icons.arrow_back,
                    color: isDark ? Colors.white : Colors.black),
                onPressed: () => _goToPage(_currentStep - 1),
              )
            : null,
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (_currentStep + 1) / 6,
            backgroundColor: isDark ? Colors.white12 : Colors.black12,
            color: AppTheme.primaryGold,
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildAccountStep(),
                _buildOtpStep(),
                _buildPersonalStep(),
                _buildVehicleStep(),
                _buildDocumentsStep(),
                _buildReviewStep(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- STEPS UI ---

  Widget _buildAccountStep() {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _header(LocalizationService.translate('create_account', lang),
              LocalizationService.translate('account_step_desc', lang)),
          const SizedBox(height: 30),
          _input(LocalizationService.translate('full_name', lang),
              _nameController, Icons.person),
          _input(LocalizationService.translate('email_address', lang),
              _emailController, Icons.email),
          _input(LocalizationService.translate('phone_number', lang),
              _phoneController, Icons.phone),
          _input(LocalizationService.translate('password', lang),
              _passwordController, Icons.lock,
              isPass: true),
          const SizedBox(height: 30),
          _isLoading
              ? const CircularProgressIndicator()
              : _btn(
                  LocalizationService.translate('continue', lang), _nextStep),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _header(
              LocalizationService.translate('verify_email', lang),
              LocalizationService.translate('verify_email_desc', lang)
                  .replaceFirst('{email}', _emailController.text)),
          const SizedBox(height: 40),
          TextField(
            controller: _otpController,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 32,
                letterSpacing: 15),
            decoration: InputDecoration(
                counterText: "",
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                        color: isDark ? Colors.white24 : Colors.black26))),
          ),
          const SizedBox(height: 40),
          _isLoading 
            ? const CircularProgressIndicator()
            : _btn(LocalizationService.translate('verify_otp_btn', lang), _nextStep),
          const SizedBox(height: 20),
          TextButton(
              onPressed: () async {
                setState(() => _isLoading = true);
                await DatabaseService.instance.sendEmailOTP(_emailController.text);
                if (mounted) setState(() => _isLoading = false);
              },
              child: Text(LocalizationService.translate('resend_otp', lang),
                  style: const TextStyle(color: AppTheme.primaryGold)))
        ],
      ),
    );
  }

  Widget _buildPersonalStep() {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _header(LocalizationService.translate('personal_info', lang),
              LocalizationService.translate('tell_us_about_yourself', lang)),
          const SizedBox(height: 30),
          _dropdown(
              LocalizationService.translate('gender', lang),
              [
                LocalizationService.translate('male', lang),
                LocalizationService.translate('female', lang)
              ],
              (v) => setState(() => _selectedGender = v)),
          const SizedBox(height: 20),
          _dropdown(
              LocalizationService.translate('region', lang),
              ["Dar es Salaam", "Arusha", "Mwanza", "Dodoma"],
              (v) => setState(() => _selectedRegion = v)),
          _input(LocalizationService.translate('city_district', lang),
              _cityController, Icons.location_city),
          const SizedBox(height: 30),
          _btn(LocalizationService.translate('continue', lang), _nextStep),
        ],
      ),
    );
  }

  Widget _buildVehicleStep() {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _header(LocalizationService.translate('vehicle_details', lang),
              LocalizationService.translate('car_details_desc', lang)),
          const SizedBox(height: 30),
          _input(LocalizationService.translate('vehicle_model_label', lang),
              _carModelController, Icons.directions_car),
          _input(LocalizationService.translate('plate_number_label', lang),
              _plateNumberController, Icons.pin),
          _input(LocalizationService.translate('color', lang), _colorController,
              Icons.color_lens),
          _input(LocalizationService.translate('year_of_manufacture', lang),
              _yearController, Icons.calendar_today),
          _dropdown(
              LocalizationService.translate('service_type', lang),
              ["BODABODA", "BAJAJI", "CAR", "XL"],
              (v) => setState(() => _selectedVehicleType = v)),
          const SizedBox(height: 20),
          _uploadBox(
              LocalizationService.translate('vehicle_photo', lang),
              kIsWeb ? _vehiclePhotoWeb != null : _vehiclePhoto != null,
              () => _pickImg('vehicle')),
          const SizedBox(height: 30),
          _btn(LocalizationService.translate('continue', lang), _nextStep),
        ],
      ),
    );
  }

  Widget _buildDocumentsStep() {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _header(LocalizationService.translate('important_documents', lang),
              LocalizationService.translate('verification_docs_desc', lang)),
          const SizedBox(height: 20),
          _uploadBox(
              LocalizationService.translate('driving_license', lang),
              kIsWeb ? _licensePhotoWeb != null : _licensePhoto != null,
              () => _pickImg('license')),
          _uploadBox(
              LocalizationService.translate('insurance_doc', lang),
              kIsWeb ? _insurancePhotoWeb != null : _insurancePhoto != null,
              () => _pickImg('insurance')),
          _uploadBox(
              LocalizationService.translate('nida_id', lang),
              kIsWeb ? _idPhotoWeb != null : _idPhoto != null,
              () => _pickImg('id')),
          _uploadBox(
              LocalizationService.translate('profile_photo', lang),
              kIsWeb ? _profilePhotoWeb != null : _profilePhoto != null,
              () => _pickImg('profile')),
          const SizedBox(height: 30),
          _btn(LocalizationService.translate('verify_continue', lang),
              _nextStep),
        ],
      ),
    );
  }

  Widget _buildReviewStep() {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _header(LocalizationService.translate('review_submit', lang),
              LocalizationService.translate('review_desc', lang)),
          const SizedBox(height: 20),
          _reviewTile(LocalizationService.translate('full_name', lang),
              _nameController.text),
          _reviewTile(LocalizationService.translate('vehicle', lang),
              "${_carModelController.text} (${_plateNumberController.text})"),
          _reviewTile(LocalizationService.translate('region', lang),
              _selectedRegion ?? ""),
          const SizedBox(height: 40),
          _isLoading
              ? const CircularProgressIndicator()
              : _btn(LocalizationService.translate('submit_application', lang),
                  _submitAll),
        ],
      ),
    );
  }

  Future<void> _submitAll() async {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final String uid = auth.currentUser!.id;

      // 1. Helper function for reliable upload with validation
      Future<String?> upload(dynamic file, String docName) async {
        if (file == null) return null;
        final url = await DatabaseService.instance.uploadDriverDocument(
          uid,
          docName,
          file,
        );
        if (url == null || url.isEmpty) {
          throw Exception("Failed to upload $docName");
        }
        return url;
      }

      // 2. Upload with strict check for required files
      String? licenseUrlStr;
      String? profileUrl;
      String? insuranceUrlStr;
      String? idUrlStr;
      String? vehicleUrl;

      try {
        // MUHIMU: Tunahakikisha picha zote zinapakiwa na kupata URL za mtandaoni
        debugPrint("Uploading documents to PostgreSQL...");
        
        licenseUrlStr = await upload(
            kIsWeb ? _licensePhotoWeb : _licensePhoto, "license_${uid}.jpg");
            
        profileUrl = await upload(
            kIsWeb ? _profilePhotoWeb : _profilePhoto, "profile_${uid}.jpg");

        // Optional docs (Picha ya gari pia inapakiwa hapa)
        insuranceUrlStr = await upload(
            kIsWeb ? _insurancePhotoWeb : _insurancePhoto, "insurance_${uid}.jpg");
            
        idUrlStr = await upload(
            kIsWeb ? _idPhotoWeb : _idPhoto, "nida_${uid}.jpg");
            
        vehicleUrl = await upload(
            kIsWeb ? _vehiclePhotoWeb : _vehiclePhoto, "vehicle_${uid}.jpg");
            
        debugPrint("Upload complete. Profile URL: $profileUrl");
      } catch (e) {
        _showError(
            "${LocalizationService.translate('upload_failed', lang)}: ${e.toString()}");
        return;
      }

      // 3. Update Firestore Profile only if essential uploads succeeded
      if (licenseUrlStr == null || profileUrl == null) {
        _showError(LocalizationService.translate('docs_required', lang));
        return;
      }
      await auth.updateProfile(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        gender: _selectedGender,
        carModel: _carModelController.text.trim(),
        carPlate: _plateNumberController.text.trim(),
        carColor: _colorController.text.trim(),
        carYear: _yearController.text.trim(),
        vehicleType: _selectedVehicleType,
        profileImageUrl: profileUrl,
        licenseUrl: licenseUrlStr,
        insuranceUrl: insuranceUrlStr,
        nationalIdUrl: idUrlStr,
        vehiclePhotoUrl: vehicleUrl,
        region: _selectedRegion,
        city: _cityController.text.trim(),
      );

      // Final save for verification status
      await DatabaseService.instance.updateDriverVerificationStatus(
          uid, 'pending');

      // Simulation of STK Push or Success notification
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocalizationService.translate(
                'application_submitted_msg', lang)),
            backgroundColor: Colors.green,
          ),
        );
      }

      if (mounted) Navigator.pushReplacementNamed(context, '/driver-home');
    } catch (e) {
      _showError(
          "${LocalizationService.translate('error_occurred', lang).replaceFirst('{error}', '')}: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- HELPERS ---

  Widget _header(String t, String s) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t,
          style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryGold)),
      Text(s,
          style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
    ]);
  }

  Widget _input(String l, TextEditingController c, IconData i,
      {bool isPass = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: c,
        obscureText: isPass,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          labelText: l,
          labelStyle:
              TextStyle(color: isDark ? Colors.white54 : Colors.black54),
          prefixIcon: Icon(i, color: AppTheme.primaryGold),
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _dropdown(String l, List<String> items, Function(String?) onC) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      child: DropdownButtonFormField<String>(
        dropdownColor: isDark ? AppTheme.surfaceGrey : Colors.white,
        decoration: InputDecoration(
            labelText: l,
            labelStyle:
                TextStyle(color: isDark ? Colors.white54 : Colors.black54),
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none)),
        items: items
            .map((e) => DropdownMenuItem(
                value: e,
                child: Text(e,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black))))
            .toList(),
        onChanged: onC,
      ),
    );
  }

  Widget _uploadBox(String l, bool hasFile, VoidCallback onT) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onT,
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: !hasFile
                    ? (isDark ? Colors.white12 : Colors.black12)
                    : Colors.green)),
        child: Row(children: [
          Icon(!hasFile ? Icons.upload_file : Icons.check_circle,
              color: !hasFile
                  ? (isDark ? Colors.white54 : Colors.black54)
                  : Colors.green),
          const SizedBox(width: 15),
          Text(l,
              style:
                  TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
        ]),
      ),
    );
  }

  Widget _reviewTile(String l, String v) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
        title: Text(l,
            style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54, fontSize: 12)),
        subtitle: Text(v,
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.bold)));
  }

  Widget _btn(String l, VoidCallback onT) {
    return SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
            onPressed: onT,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGold,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: Text(l,
                style: const TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold))));
  }

  Future<void> _pickImg(String type) async {
    final p = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (p != null) {
      if (kIsWeb) {
        final bytes = await p.readAsBytes();
        setState(() {
          if (type == 'vehicle') _vehiclePhotoWeb = bytes;
          if (type == 'license') _licensePhotoWeb = bytes;
          if (type == 'insurance') _insurancePhotoWeb = bytes;
          if (type == 'id') _idPhotoWeb = bytes;
          if (type == 'profile') _profilePhotoWeb = bytes;
        });
      } else {
        setState(() {
          if (type == 'vehicle') _vehiclePhoto = File(p.path);
          if (type == 'license') _licensePhoto = File(p.path);
          if (type == 'insurance') _insurancePhoto = File(p.path);
          if (type == 'id') _idPhoto = File(p.path);
          if (type == 'profile') _profilePhoto = File(p.path);
        });
      }
    }
  }
}
