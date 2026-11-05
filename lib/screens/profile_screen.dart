import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import '../services/database_service.dart';
import '../services/localization_service.dart';
import '../utils/theme.dart';
import '../widgets/profile_image_widget.dart';

class ProfileScreen extends StatefulWidget {
  final bool mustCompleteProfile;
  const ProfileScreen({super.key, this.mustCompleteProfile = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _carModelController;
  late TextEditingController _carPlateController;
  late TextEditingController _carColorController;
  late TextEditingController _payoutNumberController;
  // Removed unused _isDarkMode and _selectedLanguage fields
  String? _selectedVehicleType;
  String? _selectedGender;
  String? _selectedPayoutMethod;
  bool _isEditing = false;
  File? _imageFile;
  Uint8List? _webImageBytes;
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _recentTrips = [];

  final List<Map<String, String>> _vehicleTypes = [
    {'id': 'Car', 'name': 'standard_car'},
    {'id': 'Bajaji', 'name': 'bajaji_3wheeler'},
    {'id': 'Bodaboda', 'name': 'bodaboda_motorbike'},
    {'id': 'XL', 'name': 'sta_xl_suv_long'},
    {'id': 'Send', 'name': 'sta_send_delivery'},
  ];

  @override
  void initState() {
    super.initState();
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    _nameController = TextEditingController(text: user?.name);
    _emailController = TextEditingController(text: user?.email);
    _phoneController = TextEditingController(text: user?.phoneNumber);
    _carModelController = TextEditingController(text: user?.carModel);
    _carPlateController = TextEditingController(text: user?.carPlate);
    _carColorController = TextEditingController(text: user?.carColor);
    _payoutNumberController = TextEditingController(text: user?.payoutNumber);
    
    // Normalization to prevent "Bad State: No element" or Dropdown Assertion errors
    if (user?.vehicleType != null) {
      try {
        _selectedVehicleType = _vehicleTypes.firstWhere(
          (t) => t['id']?.toLowerCase() == user!.vehicleType!.toLowerCase(),
          orElse: () => _vehicleTypes[0]
        )['id'];
      } catch (e) {
        _selectedVehicleType = 'Car';
      }
    } else {
      _selectedVehicleType = 'Car';
    }

    _selectedGender = user?.gender;
    _selectedPayoutMethod = user?.payoutMethod ?? 'M-Pesa';
    if (widget.mustCompleteProfile) {
      _isEditing = true;
    }
    _fetchRecentTrips();
  }

  Future<void> _fetchRecentTrips() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.currentUser == null) return;
    
    try {
      final trips = await DatabaseService.instance.getAllTrips(
        riderId: auth.currentUser!.role == UserRole.rider ? auth.currentUser!.id : null,
        driverId: auth.currentUser!.role == UserRole.driver ? auth.currentUser!.id : null,
      );
      
      if (mounted) {
        setState(() {
          // Chukua maeneo 3 ya mwisho ya kipekee (Unique dropoffs)
          final seen = <String>{};
          _recentTrips = trips
              .where((t) => t['dropoff'] != null && t['dropoff'] != 'Unknown Destination')
              .map((t) {
                String addr = t['dropoff'].toString();
                // If it looks like raw coordinates "lat,lng", show a placeholder or "Pinned Location"
                if (addr.contains(',') && double.tryParse(addr.split(',')[0].trim()) != null) {
                  addr = LocalizationService.translate('pinned_location', auth.language);
                }
                return {'address': addr};
              })
              .where((t) => seen.add(t['address'] as String))
              .take(3)
              .toList();
        });
      }
    } catch (e) {
      // Error fetching trips
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _carModelController.dispose();
    _carPlateController.dispose();
    _carColorController.dispose();
    _payoutNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? pickedFile =
        await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _webImageBytes = bytes;
        });
      }
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final user = auth.currentUser;
      if (user == null) return;

      String? finalUrl = user.profileImageUrl;
      if (_imageFile != null) {
        finalUrl = await DatabaseService.instance.uploadDriverDocument(
          user.id,
          "profile_${DateTime.now().millisecondsSinceEpoch}.jpg",
          kIsWeb ? _webImageBytes : File(_imageFile!.path),
        );
      }

      // Kama ni Driver na anasubmit mabadiliko
      if (user.role == UserRole.driver && user.profileEditStatus == 'allowed') {
        final updates = {
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'carModel': _carModelController.text.trim(),
          'carPlate': _carPlateController.text.trim(),
          'carColor': _carColorController.text.trim(),
          'vehicleType': _selectedVehicleType,
          'payoutNumber': _payoutNumberController.text.trim(),
          'payoutMethod': _selectedPayoutMethod,
          'gender': _selectedGender,
          'profileImageUrl': finalUrl,
        };

        await DatabaseService.instance.submitDriverProfileEdit(user.id, updates);

        if (!mounted) return;
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(LocalizationService.translate(
                  'update_submitted_for_review', auth.language)),
              backgroundColor: Colors.blue),
        );
        return;
      }

      final success = await auth.updateProfile(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        gender: _selectedGender,
        profileImageUrl: finalUrl,
        updatePhotoTimestamp: _imageFile != null,
        carModel: auth.currentUser?.role == UserRole.driver
            ? _carModelController.text.trim()
            : null,
        carPlate: auth.currentUser?.role == UserRole.driver
            ? _carPlateController.text.trim()
            : null,
        carColor: auth.currentUser?.role == UserRole.driver
            ? _carColorController.text.trim()
            : null,
        vehicleType: auth.currentUser?.role == UserRole.driver
            ? _selectedVehicleType
            : null,
        payoutNumber: auth.currentUser?.role == UserRole.driver
            ? _payoutNumberController.text.trim()
            : null,
        payoutMethod: auth.currentUser?.role == UserRole.driver
            ? _selectedPayoutMethod
            : null,
      );

      if (success) {
        if (!mounted) return;
        setState(() {
          _isEditing = false;
          _imageFile = null;
          _webImageBytes = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(LocalizationService.translate(
                  'profile_updated', auth.language)),
              backgroundColor: Colors.green),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(LocalizationService.translate(
                  'profile_update_failed', auth.language)),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateAddress(String type) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final lang = auth.language;

    final result = await Navigator.pushNamed(
      context,
      '/location-picker',
      arguments: {
        'title': type == 'Home'
            ? LocalizationService.translate('home', lang)
            : LocalizationService.translate('work', lang),
      },
    );

    if (result != null && result is Map) {
      final newAddress = result['address'] as String;
      final success = await auth.updateProfile(
        name: auth.currentUser!.name,
        email: auth.currentUser!.email,
        phoneNumber: auth.currentUser!.phoneNumber,
        homeAddress:
            type == 'Home' ? newAddress : auth.currentUser?.homeAddress,
        workAddress:
            type == 'Work' ? newAddress : auth.currentUser?.workAddress,
      );

      if (mounted && success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(LocalizationService.translate('profile_updated', lang)),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _showComingSoon(String lang) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(LocalizationService.translate('feature_coming_soon', lang)),
        backgroundColor: _accentGold,
      ),
    );
  }

  void _showSafetyInfo(String lang) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? _bgBrown : Colors.white,
        title: Text(LocalizationService.translate('safety_center', lang),
            style: TextStyle(color: _accentGold, fontWeight: FontWeight.bold)),
        content: Text(
          lang == 'Kiswahili'
              ? "Usalama wako ni kipaumbele chetu. Wakati wa safari, unaweza kubonyeza kitufe cha SOS kutuma eneo lako kwa mamlaka na watu wako wa karibu."
              : "Your safety is our priority. During a ride, you can use the SOS button to share your location with authorities and emergency contacts.",
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("OK", style: TextStyle(color: _accentGold)))
        ],
      ),
    );
  }

  void _showAboutDialog(String lang) {
    showAboutDialog(
      context: context,
      applicationName: "STA RIDE",
      applicationVersion: "1.0.0",
      applicationLegalese: "© 2024 Smart Transport App",
      children: [
        Text(
          lang == 'Kiswahili'
            ? "STA RIDE ni mfumo wa kisasa wa usafiri nchini Tanzania unaotoa huduma bora na salama."
            : "STA RIDE is a modern transport system in Tanzania providing quality and secure services.",
        ),
      ],
    );
  }

  final Color _bgBrown = const Color(0xFF2B2B2B);
  final Color _accentGold = AppTheme.primaryGold;

  Future<void> _requestProfileEdit() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await DatabaseService.instance.requestDriverProfileEdit(auth.currentUser!.id);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(LocalizationService.translate('edit_requested', auth.language)),
        backgroundColor: Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.currentUser;
    final lang = authProvider.language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (user == null) {
      return Scaffold(
        backgroundColor: isDark ? _bgBrown : Colors.white,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? _bgBrown : Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          LocalizationService.translate('my_account', lang),
          style: GoogleFonts.poppins(
            color: _accentGold,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        actions: [
          if (user.role == UserRole.driver && user.profileEditStatus == 'none' && !_isEditing)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: _requestProfileEdit,
                icon: const Icon(Icons.lock_open, size: 18, color: Colors.orange),
                label: Text(
                  LocalizationService.translate('request_edit', lang),
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: Colors.orange, width: 1),
                  ),
                ),
              ),
            ),
          if (!_isEditing)
            IconButton(
              icon: Icon(Icons.edit, color: isDark ? Colors.white : Colors.black),
              onPressed: () => setState(() => _isEditing = true),
            ),
          if (_isEditing && (user.role != UserRole.driver || user.profileEditStatus == 'allowed' || widget.mustCompleteProfile))
            IconButton(
              icon: Icon(Icons.save, color: isDark ? Colors.white : Colors.black),
              onPressed: _saveProfile,
            ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: isDark ? const RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [Color(0xFF7A4B13), Color(0xFF4B2E0B)],
          ) : null,
          color: isDark ? null : Theme.of(context).scaffoldBackgroundColor,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Profile header
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Column(
                    children: [
                      if (user.role == UserRole.driver && user.profileEditStatus == 'requested')
                         Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Chip(
                            label: Text(LocalizationService.translate('edit_pending_approval', lang)),
                            backgroundColor: Colors.orange.withValues(alpha: 0.1),
                            labelStyle: const TextStyle(color: Colors.orange, fontSize: 12),
                          ),
                        ),
                      if (user.role == UserRole.driver && user.profileEditStatus == 'submitted')
                         Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Chip(
                            label: Text(LocalizationService.translate('changes_under_review', lang)),
                            backgroundColor: Colors.blue.withValues(alpha: 0.1),
                            labelStyle: const TextStyle(color: Colors.blue, fontSize: 12),
                          ),
                        ),
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: _accentGold, width: 3),
                              boxShadow: isDark ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 15,
                                  spreadRadius: 2,
                                ),
                              ] : [],
                            ),
                            child: ProfileImageWidget(
                              imageUrl: _imageFile?.path ?? user.profileImageUrl,
                              imageBytes: _webImageBytes,
                              name: user.name,
                              radius: 50,
                            ),
                          ),
                          if (_isEditing)
                            GestureDetector(
                              onTap: _pickImage,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: _accentGold,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: isDark ? Colors.black : Colors.white, width: 2)),
                                child: const Icon(Icons.camera_alt,
                                    size: 20, color: Colors.black),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Text(
                        (user.name.isNotEmpty)
                            ? user.name
                            : LocalizationService.translate('sta_user', lang),
                        style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : Colors.black),
                      ),
                      if (user.role == UserRole.driver && user.carModel != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            "${user.carModel} • ${user.carPlate ?? ''}",
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: _accentGold,
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                      Text(
                        user.phoneNumber,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : Colors.black54,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),

                if (_isEditing)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 25, vertical: 10),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _buildProfileField(
                              _nameController,
                              LocalizationService.translate('full_name', lang),
                              Icons.person,
                              lang,
                              isDark,
                              enabled: user.role != UserRole.driver || user.profileEditStatus == 'allowed' || widget.mustCompleteProfile), // Enable if allowed or forced
                          const SizedBox(height: 15),
                          _buildProfileField(
                              _emailController,
                              LocalizationService.translate('email', lang),
                              Icons.email,
                              lang,
                              isDark,
                              keyboardType: TextInputType.emailAddress,
                              enabled: user.role != UserRole.driver || user.profileEditStatus == 'allowed' || widget.mustCompleteProfile), // Enable if allowed or forced
                          const SizedBox(height: 15),
                          _buildProfileField(
                              _phoneController,
                              LocalizationService.translate(
                                  'phone_number', lang),
                              Icons.phone,
                              lang,
                              isDark,
                              keyboardType: TextInputType.phone,
                              enabled: widget.mustCompleteProfile), // Phone number typically locked, unless forced to complete
                          const SizedBox(height: 15),
                          _buildGenderDropdown(lang, isDark, enabled: user.role != UserRole.driver || user.profileEditStatus == 'allowed' || widget.mustCompleteProfile),
                          if (user.role == UserRole.driver) ...[
                            const SizedBox(height: 10),
                            if (user.profileEditStatus != 'allowed')
                              Text(
                                lang == 'Kiswahili' 
                                  ? "* Taarifa za chombo na akaunti hurekebishwa na Admin pekee."
                                  : "* Vehicle and account info can only be updated by Admin.",
                                style: GoogleFonts.poppins(color: _accentGold, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            const SizedBox(height: 10),
                            _buildVehicleTypeDropdown(lang, isDark, enabled: user.profileEditStatus == 'allowed'),
                            const SizedBox(height: 15),
                            _buildProfileField(
                                _carModelController,
                                LocalizationService.translate('model', lang),
                                Icons.directions_car,
                                lang,
                                isDark,
                                enabled: user.profileEditStatus == 'allowed'),
                            const SizedBox(height: 15),
                            _buildProfileField(
                                _carPlateController,
                                LocalizationService.translate('plate', lang),
                                Icons.tag,
                                lang,
                                isDark,
                                enabled: user.profileEditStatus == 'allowed'),
                            const SizedBox(height: 15),
                            _buildProfileField(
                                _carColorController,
                                LocalizationService.translate('color', lang),
                                Icons.color_lens,
                                lang,
                                isDark,
                                enabled: user.profileEditStatus == 'allowed'),
                            const SizedBox(height: 15),
                            _buildPayoutMethodDropdown(lang, isDark, enabled: user.profileEditStatus == 'allowed'),
                            const SizedBox(height: 15),
                            _buildProfileField(
                                _payoutNumberController,
                                LocalizationService.translate('payout_number', lang),
                                Icons.account_balance_wallet,
                                lang,
                                isDark,
                                keyboardType: TextInputType.phone,
                                enabled: user.profileEditStatus == 'allowed'),
                          ],
                          const SizedBox(height: 30),
                          if (user.role != UserRole.driver || user.profileEditStatus == 'allowed' || widget.mustCompleteProfile)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _saveProfile,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accentGold,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                      side: BorderSide(
                                          color: isDark ? Colors.black : Colors.white, width: 2)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                ),
                                child: Text(
                                  LocalizationService.translate(
                                      'save_changes', lang),
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          if (user.role == UserRole.driver && user.profileEditStatus == 'none')
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _requestProfileEdit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                      side: BorderSide(
                                          color: isDark ? Colors.black : Colors.white, width: 2)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                ),
                                child: Text(
                                  LocalizationService.translate(
                                      'request_edit', lang),
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          if (!widget.mustCompleteProfile)
                            TextButton(
                                onPressed: () =>
                                    setState(() => _isEditing = false),
                                child: Text(
                                    LocalizationService.translate(
                                        'cancel', lang),
                                    style:
                                        TextStyle(color: isDark ? Colors.white60 : Colors.black54)))
                        ],
                      ),
                    ),
                  )
                else
                  Column(
                    children: [
                      if (widget.mustCompleteProfile)
                        Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                                color: Colors.red.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: Colors.redAccent),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  LocalizationService.translate(
                                      'complete_profile_msg', lang),
                                  style: GoogleFonts.poppins(
                                      color: isDark ? Colors.white : Colors.black, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (user.role == UserRole.driver) ...[
                        _buildSectionTitle(
                            LocalizationService.translate('driver_level', lang)),
                        _buildDriverLevelCard(user, lang, isDark),
                      ],
                      _buildSectionTitle(
                          LocalizationService.translate('saved_places', lang)),
                      _buildSavedPlaceCard(
                          Icons.home_filled,
                          LocalizationService.translate('home', lang),
                          user.homeAddress ?? LocalizationService.translate('add_home', lang),
                          () => _updateAddress('Home'),
                          isDark),
                      const SizedBox(height: 10),
                      _buildSavedPlaceCard(
                          Icons.work,
                          LocalizationService.translate('work', lang),
                          user.workAddress ?? LocalizationService.translate('add_work', lang),
                          () => _updateAddress('Work'),
                          isDark),
                      
                      if (_recentTrips.isNotEmpty) ...[
                        _buildSectionTitle(LocalizationService.translate('recent_destinations', lang)),
                        ..._recentTrips.map((trip) => _buildRecentDestinationItem(trip['address'], isDark, lang)),
                      ],

                      _buildSectionTitle(
                          LocalizationService.translate('preferences', lang)),
                      _buildLanguageToggle(authProvider, isDark),
                      _buildThemeToggle(authProvider, isDark),
                      _buildSectionTitle(
                          LocalizationService.translate('payment_trips', lang)),
                      _buildMenuItem(
                          Icons.account_balance_wallet_outlined,
                          LocalizationService.translate(
                                  user.role == UserRole.driver
                                      ? 'wallet_title'
                                      : 'payment_methods',
                                  lang)
                              .toUpperCase(),
                          () => Navigator.pushNamed(context, '/wallet'),
                          isDark: isDark),
                      if (user.role != UserRole.driver)
                        _buildMenuItem(
                            Icons.local_offer,
                            LocalizationService.translate('promotions', lang)
                                .toUpperCase(),
                            () => Navigator.pushNamed(context, '/promotions'),
                            isDark: isDark),
                      _buildMenuItem(
                          Icons.history,
                          LocalizationService.translate(
                                  user.role == UserRole.driver
                                      ? 'trip_history'
                                      : 'ride_history',
                                  lang)
                              .toUpperCase(),
                          () {
                        if (user.role == UserRole.driver) {
                          Navigator.pushNamed(context, '/driver-history',
                              arguments: user.id);
                        } else {
                          Navigator.pushNamed(context, '/rider-history',
                              arguments: user.id);
                        }
                      }, isDark: isDark),
                      _buildSectionTitle(LocalizationService.translate(
                          'safety_support', lang)),
                      _buildMenuItem(
                          Icons.security,
                          LocalizationService.translate('safety_center', lang)
                              .toUpperCase(),
                          () => Navigator.pushNamed(context, '/safety'),
                          isDark: isDark),
                      _buildMenuItem(
                          Icons.support_agent,
                          LocalizationService.translate(
                                  'customer_support', lang)
                              .toUpperCase(),
                          () => Navigator.pushNamed(context, '/support'),
                          isDark: isDark),
                      _buildMenuItem(
                          Icons.info_outline,
                          LocalizationService.translate('about_sta', lang)
                              .toUpperCase(),
                          () => Navigator.pushNamed(context, '/about'),
                          isDark: isDark),
                      const Padding(
                          padding: EdgeInsets.symmetric(
                              vertical: 10, horizontal: 25),
                          child: Divider(color: Colors.white10)),
                      if (user.role == UserRole.driver) ...[
                        _buildSectionTitle(
                            LocalizationService.translate('vehicle_info', lang)
                                .toUpperCase()),
                        _buildMenuItem(
                            Icons.directions_car, user.carModel ?? 'N/A', () {},
                            subtitle:
                                LocalizationService.translate('model', lang),
                            isDark: isDark),
                        _buildMenuItem(Icons.tag, user.carPlate ?? 'N/A', () {},
                            subtitle:
                                LocalizationService.translate('plate', lang),
                            isDark: isDark),
                        _buildMenuItem(
                            Icons.color_lens, user.carColor ?? 'N/A', () {},
                            subtitle:
                                LocalizationService.translate('color', lang),
                            isDark: isDark),
                        _buildMenuItem(
                            Icons.category,
                            LocalizationService.translate(
                                user.vehicleType != null
                                    ? (_vehicleTypes.firstWhere(
                                        (t) =>
                                            t['id']?.toLowerCase() ==
                                            user.vehicleType?.toLowerCase(),
                                        orElse: () => _vehicleTypes[0])['name']!)
                                    : 'standard_car',
                                lang),
                            () {},
                            subtitle: LocalizationService.translate(
                                'vehicle_type', lang),
                            isDark: isDark),
                      ],
                      if (user.role != UserRole.driver)
                        _buildMenuItem(
                          Icons.directions_car,
                          LocalizationService.translate('switch_driver', lang),
                          () => Navigator.pushNamed(context, '/driver-auth'),
                          iconColor: _accentGold,
                          isDark: isDark,
                        ),
                      _buildMenuItem(
                        Icons.logout,
                        LocalizationService.translate('logout', lang),
                        () async {
                          await authProvider.logout();
                          if (context.mounted) {
                            Navigator.pushNamedAndRemoveUntil(
                                context, '/', (route) => false);
                          }
                        },
                        iconColor: Colors.redAccent,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 50),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(25, 30, 25, 10),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: _accentGold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildDriverLevelCard(UserModel user, String lang, bool isDark) {
    final level = user.driverLevel ?? 'Bronze';
    Color levelColor;
    switch (level.toLowerCase()) {
      case 'gold':
        levelColor = Colors.amber;
        break;
      case 'silver':
        levelColor = Colors.grey.shade400;
        break;
      default:
        levelColor = const Color(0xFFCD7F32); // Bronze
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 5),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: levelColor.withValues(alpha: 0.5), width: 2),
        boxShadow: [
          BoxShadow(
            color: levelColor.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.stars, color: levelColor, size: 30),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocalizationService.translate(level.toLowerCase(), lang),
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  LocalizationService.translate('driver_level_desc', lang),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              Text(
                user.rating.toStringAsFixed(1),
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _accentGold,
                ),
              ),
              const Icon(Icons.star, color: Colors.amber, size: 16),
            ],
          ),
          const SizedBox(width: 5),
        ],
      ),
    );
  }

  Widget _buildLanguageToggle(AuthProvider auth, bool isDark) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 25),
      leading: _menuIconContainer(Icons.language, null, isDark),
      title: Text(LocalizationService.translate('language', auth.language),
          style: GoogleFonts.poppins(
              color: isDark ? Colors.white : Colors.black, fontSize: 15, fontWeight: FontWeight.w900)),
      trailing: DropdownButton<String>(
        value: auth.language,
        dropdownColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        underline: const SizedBox(),
        style: TextStyle(color: _accentGold, fontWeight: FontWeight.w900),
        items: ['English', 'Kiswahili'].map((String value) {
          return DropdownMenuItem<String>(value: value, child: Text(value, style: TextStyle(color: isDark ? _accentGold : Colors.black87)));
        }).toList(),
        onChanged: (val) => auth.setLanguage(val!),
      ),
    );
  }

  Widget _buildThemeToggle(AuthProvider auth, bool isDark) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 25),
      leading:
          _menuIconContainer(isDark ? Icons.dark_mode : Icons.light_mode, null, isDark),
      title: Text(LocalizationService.translate('dark_mode', auth.language),
          style: GoogleFonts.poppins(
              color: isDark ? Colors.white : Colors.black, fontSize: 15, fontWeight: FontWeight.w900)),
      trailing: Switch(
        value: isDark,
        activeTrackColor: _accentGold,
        onChanged: (val) => auth.toggleTheme(val),
      ),
    );
  }

  Widget _menuIconContainer(IconData icon, Color? iconColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2B2B2B) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.black : Colors.grey.shade300, width: 2),
      ),
      child: Icon(icon, color: iconColor ?? _accentGold, size: 22),
    );
  }

  Widget _buildMenuItem(IconData icon, String title, VoidCallback onTap,
      {Color? iconColor, String? subtitle, required bool isDark}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 25),
      leading: _menuIconContainer(icon, iconColor, isDark),
      title: Text(title,
          style: GoogleFonts.poppins(
              fontSize: 15, color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.w900)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.w500))
          : null,
      trailing:
          Icon(Icons.arrow_forward_ios, color: isDark ? Colors.white24 : Colors.black26, size: 14),
      onTap: onTap,
    );
  }

  Widget _buildProfileField(TextEditingController controller, String label,
      IconData icon, String lang, bool isDark,
      {TextInputType keyboardType = TextInputType.text, bool enabled = true}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: (isDark ? Colors.black26 : Colors.grey.shade100)
            .withOpacity(enabled ? 1.0 : 0.5),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
            color: (isDark ? Colors.white70 : Colors.black12)
                .withOpacity(enabled ? 1.0 : 0.5)),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        enabled: enabled,
        style: TextStyle(
            color: (isDark ? Colors.white : Colors.black)
                .withOpacity(enabled ? 1.0 : 0.6),
            fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
              color: (isDark ? Colors.white54 : Colors.black54)
                  .withOpacity(enabled ? 1.0 : 0.6),
              fontSize: 12),
          prefixIcon: Icon(icon,
              color: _accentGold.withOpacity(enabled ? 1.0 : 0.5), size: 20),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: _accentGold, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        validator: (value) => value == null || value.isEmpty
            ? LocalizationService.translate('field_required', lang)
            : null,
      ),
    );
  }

  Widget _buildGenderDropdown(String lang, bool isDark, {bool enabled = true}) {
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? Colors.black26 : Colors.grey.shade100).withOpacity(enabled ? 1.0 : 0.5),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: (isDark ? Colors.white10 : Colors.black12).withOpacity(enabled ? 1.0 : 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: DropdownButtonFormField<String>(
        value: _selectedGender,
        dropdownColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        decoration: InputDecoration(
          labelText: LocalizationService.translate('gender', lang),
          labelStyle: TextStyle(color: (isDark ? Colors.white54 : Colors.black54).withOpacity(enabled ? 1.0 : 0.6), fontSize: 12),
          prefixIcon: Icon(Icons.people, color: _accentGold.withOpacity(enabled ? 1.0 : 0.5), size: 20),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: _accentGold, width: 1.5),
          ),
        ),
        items: ['Male', 'Female'].map((String value) {
          return DropdownMenuItem<String>(
            value: value,
            child: Text(
                LocalizationService.translate(value.toLowerCase(), lang),
                style: TextStyle(color: (isDark ? Colors.white : Colors.black).withOpacity(enabled ? 1.0 : 0.6), fontSize: 14)),
          );
        }).toList(),
        onChanged: enabled ? (val) => setState(() => _selectedGender = val) : null,
        validator: (value) => value == null
            ? LocalizationService.translate('select_gender_err', lang)
            : null,
      ),
    );
  }

  Widget _buildSavedPlaceCard(IconData icon, String title, String subtitle, VoidCallback? onTap, bool isDark) {
    final String homeAdd = LocalizationService.translate('add_home', 'English');
    final String workAdd = LocalizationService.translate('add_work', 'English');
    final String homeAddSw = LocalizationService.translate('add_home', 'Kiswahili');
    final String workAddSw = LocalizationService.translate('add_work', 'Kiswahili');
    final String fetching = LocalizationService.translate('fetching_address', 'English');
    final String fetchingSw = LocalizationService.translate('fetching_address', 'Kiswahili');

    final bool isAddressSet = subtitle.isNotEmpty && 
                             subtitle != homeAdd && 
                             subtitle != workAdd &&
                             subtitle != homeAddSw &&
                             subtitle != workAddSw &&
                             subtitle != fetching &&
                             subtitle != fetchingSw;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAddressSet ? _accentGold.withValues(alpha: 0.3) : (isDark ? Colors.white10 : Colors.black12),
          width: isAddressSet ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isAddressSet ? _accentGold.withValues(alpha: 0.1) : Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isAddressSet ? _accentGold.withValues(alpha: 0.2) : _accentGold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isAddressSet ? (title.toLowerCase().contains('home') ? Icons.home_rounded : Icons.work_rounded) : icon, 
                    color: _accentGold, 
                    size: 24
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: isAddressSet ? FontWeight.w600 : FontWeight.w400,
                          color: isAddressSet ? (isDark ? Colors.white70 : Colors.black54) : (isDark ? Colors.white54 : Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isAddressSet ? Icons.edit_location_alt : Icons.arrow_forward_ios,
                  color: isAddressSet ? _accentGold : (isDark ? Colors.white24 : Colors.black26),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentDestinationItem(String address, bool isDark, String lang) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.history, color: Colors.blue, size: 20),
        ),
        title: Text(
          address,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: isDark ? Colors.white70 : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: Icon(Icons.add_circle_outline, color: _accentGold, size: 20),
        onTap: () => _showQuickSaveDialog(address, lang, isDark),
      ),
    );
  }

  void _showQuickSaveDialog(String address, String lang, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              LocalizationService.translate('save_as', lang),
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              address,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 25),
            Row(
              children: [
                Expanded(
                  child: _quickSaveButton(Icons.home, LocalizationService.translate('home', lang), () async {
                    Navigator.pop(context);
                    await _saveQuickAddress('Home', address);
                  }),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _quickSaveButton(Icons.work, LocalizationService.translate('work', lang), () async {
                    Navigator.pop(context);
                    await _saveQuickAddress('Work', address);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _quickSaveButton(IconData icon, String label, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: _accentGold,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _saveQuickAddress(String type, String address) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final success = await auth.updateProfile(
      name: auth.currentUser!.name,
      email: auth.currentUser!.email,
      phoneNumber: auth.currentUser!.phoneNumber,
      homeAddress: type == 'Home' ? address : auth.currentUser?.homeAddress,
      workAddress: type == 'Work' ? address : auth.currentUser?.workAddress,
    );
    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LocalizationService.translate('profile_updated', auth.language)), backgroundColor: Colors.green),
      );
    }
  }

  Widget _buildVehicleTypeDropdown(String lang, bool isDark, {bool enabled = true}) {
    // Ensure the current selection is valid and normalized to match our _vehicleTypes IDs
    String? safeValue;
    if (_selectedVehicleType != null) {
      try {
        safeValue = _vehicleTypes.firstWhere(
          (t) => t['id']?.toLowerCase() == _selectedVehicleType!.toLowerCase(),
          orElse: () => _vehicleTypes[0],
        )['id'];
      } catch (_) {
        safeValue = _vehicleTypes[0]['id'];
      }
    } else {
      safeValue = _vehicleTypes[0]['id'];
    }

    return Container(
      decoration: BoxDecoration(
        color: (isDark ? Colors.black26 : Colors.grey.shade100)
            .withOpacity(enabled ? 1.0 : 0.5),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
            color: (isDark ? Colors.white70 : Colors.black12)
                .withOpacity(enabled ? 1.0 : 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: DropdownButtonFormField<String>(
        value: safeValue,
        dropdownColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        decoration: InputDecoration(
          labelText: LocalizationService.translate('vehicle_type', lang),
          labelStyle: TextStyle(
              color: (isDark ? Colors.white54 : Colors.black54)
                  .withOpacity(enabled ? 1.0 : 0.6),
              fontSize: 12),
          prefixIcon: Icon(Icons.category,
              color: _accentGold.withOpacity(enabled ? 1.0 : 0.5), size: 20),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: _accentGold, width: 1.5),
          ),
        ),
        items: _vehicleTypes.map((type) {
          return DropdownMenuItem<String>(
            value: type['id'],
            child: Text(
              LocalizationService.translate(type['name']!, lang),
              style: GoogleFonts.poppins(
                  color: (isDark ? Colors.white : Colors.black)
                      .withOpacity(enabled ? 1.0 : 0.6),
                  fontSize: 14),
            ),
          );
        }).toList(),
        onChanged: enabled
            ? (val) {
                if (val != null) {
                  setState(() => _selectedVehicleType = val);
                }
              }
            : null, // Hapa ndipo tunapozima dropdown
      ),
    );
  }

  Widget _buildPayoutMethodDropdown(String lang, bool isDark, {bool enabled = true}) {
    final List<Map<String, String>> methods = [
      {'id': 'M-Pesa', 'name': 'm_pesa'},
      {'id': 'Tigo Pesa', 'name': 'tigo_pesa'},
      {'id': 'Airtel Money', 'name': 'airtel_money'},
      {'id': 'Halo Pesa', 'name': 'halo_pesa'},
      {'id': 'Bank', 'name': 'bank_transfer'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: (isDark ? Colors.black26 : Colors.grey.shade100).withOpacity(enabled ? 1.0 : 0.5),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: (isDark ? Colors.white10 : Colors.black12).withOpacity(enabled ? 1.0 : 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: DropdownButtonFormField<String>(
        value: _selectedPayoutMethod,
        dropdownColor: isDark ? const Color(0xFF2B2B2B) : Colors.white,
        decoration: InputDecoration(
          labelText: LocalizationService.translate('payout_method', lang),
          labelStyle: TextStyle(
              color: (isDark ? Colors.white54 : Colors.black54).withOpacity(enabled ? 1.0 : 0.6), fontSize: 12),
          prefixIcon: Icon(Icons.account_balance, color: _accentGold.withOpacity(enabled ? 1.0 : 0.5), size: 20),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: _accentGold, width: 1.5),
          ),
        ),
        items: methods.map((method) {
          return DropdownMenuItem<String>(
            value: method['id'],
            child: Text(
              LocalizationService.translate(method['name']!, lang),
              style: GoogleFonts.poppins(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(enabled ? 1.0 : 0.6), fontSize: 14),
            ),
          );
        }).toList(),
        onChanged: enabled ? (val) => setState(() => _selectedPayoutMethod = val) : null,
      ),
    );
  }
}
