import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../services/localization_service.dart';
import '../widgets/profile_image_widget.dart';
import '../utils/theme.dart';

class DriverSetupProfileScreen extends StatefulWidget {
  final String driverId;
  const DriverSetupProfileScreen({super.key, required this.driverId});

  @override
  State<DriverSetupProfileScreen> createState() =>
      _DriverSetupProfileScreenState();
}

class _DriverSetupProfileScreenState extends State<DriverSetupProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _carModelController = TextEditingController();
  final _carPlateController = TextEditingController();
  final _carColorController = TextEditingController();
  String _selectedVehicleType = 'Car';

  String? _imagePath;
  Uint8List? _webImageBytes;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill fields if they already exist in current user
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      if (auth.currentUser != null) {
        setState(() {
          _carModelController.text = auth.currentUser!.carModel ?? '';
          _carPlateController.text = auth.currentUser!.carPlate ?? '';
          _carColorController.text = auth.currentUser!.carColor ?? '';
          if (auth.currentUser!.vehicleType != null) {
            // Normalization to ensure it matches one of our IDs
            const vTypes = ['Car', 'Bajaji', 'Bodaboda', 'XL', 'Send'];
            String currentType = auth.currentUser!.vehicleType!;
            _selectedVehicleType = vTypes.firstWhere(
              (t) => t.toLowerCase() == currentType.toLowerCase(),
              orElse: () => 'Car'
            );
          }
          if (auth.currentUser!.profileImageUrl != null &&
              auth.currentUser!.profileImageUrl!.isNotEmpty) {
            _imagePath = auth.currentUser!.profileImageUrl;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _carModelController.dispose();
    _carPlateController.dispose();
    _carColorController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
        source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
        imageQuality: 50);

    if (pickedFile != null) {
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _webImageBytes = bytes;
          _imagePath = pickedFile.name; // Use name as placeholder for UI
        });
      } else {
        setState(() {
          _imagePath = pickedFile.path;
        });
      }
    }
  }

  Future<void> _completeProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final lang = auth.language;

    if (_imagePath == null &&
        (auth.currentUser?.profileImageUrl == null ||
            auth.currentUser!.profileImageUrl!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                LocalizationService.translate('photo_required_msg', lang))),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      String? finalImageUrl;
      if (kIsWeb && _webImageBytes != null) {
        finalImageUrl = await DatabaseService.instance.uploadDriverDocument(
          widget.driverId,
          "profile_setup.jpg",
          _webImageBytes,
        );
      } else if (!kIsWeb &&
          _imagePath != null &&
          !_imagePath!.startsWith('http')) {
        finalImageUrl = await DatabaseService.instance.uploadDriverDocument(
          widget.driverId,
          "profile_setup.jpg",
          File(_imagePath!),
        );
      } else {
        finalImageUrl = _imagePath;
      }

      // Update AuthProvider (this updates both local and DB)
      final success = await auth.updateProfile(
        name: auth.currentUser!.name,
        email: auth.currentUser!.email,
        phoneNumber: auth.currentUser!.phoneNumber,
        profileImageUrl: finalImageUrl,
        updatePhotoTimestamp: finalImageUrl != null,
        carModel: _carModelController.text.trim(),
        carPlate: _carPlateController.text.trim(),
        carColor: _carColorController.text.trim(),
        vehicleType: _selectedVehicleType,
      );

      if (success && mounted) {
        if (finalImageUrl != null) {
          await DatabaseService.instance
              .updateAnyUserProfilePic(widget.driverId, finalImageUrl);
        }
        Navigator.pushReplacementNamed(context, '/driver-home');
      } else {
        throw Exception("Update failed");
      }
    } catch (e) {
      if (mounted) {
        final lang = auth.language;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  LocalizationService.translate('error_saving_profile', lang))),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  final Color _bgBrown = const Color(0xFF4B2E0B);
  final Color _accentGold = AppTheme.primaryGold;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final lang = auth.language;

    final List<Map<String, String>> vehicleTypes = [
      {'id': 'Car', 'name': 'standard_car'},
      {'id': 'Bajaji', 'name': 'bajaji_3wheeler'},
      {'id': 'Bodaboda', 'name': 'bodaboda_motorbike'},
      {'id': 'XL', 'name': 'sta_xl_suv_long'},
      {'id': 'Send', 'name': 'sta_send_delivery'},
    ];

    return Scaffold(
      backgroundColor: _bgBrown,
      appBar: AppBar(
        title: Text(
            LocalizationService.translate('complete_profile_title', lang),
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [const Color(0xFF7A4B13), _bgBrown],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Text(
                    LocalizationService.translate('profile_setup_desc', lang),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70, height: 1.5, fontSize: 13),
                  ),
                  const SizedBox(height: 30),
                  GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _accentGold, width: 2),
                          ),
                          child: ProfileImageWidget(
                            imageUrl: kIsWeb && _webImageBytes != null
                                ? null
                                : (_imagePath ??
                                    auth.currentUser?.profileImageUrl),
                            name: auth.currentUser?.name,
                            radius: 60,
                            iconSize: 35,
                            imageBytes: kIsWeb ? _webImageBytes : null,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _accentGold,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.black, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    _imagePath == null
                        ? LocalizationService.translate('tap_to_capture', lang)
                        : LocalizationService.translate('photo_captured', lang),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:
                          _imagePath == null ? Colors.white60 : _accentGold,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Vehicle Details Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: Colors.black, width: 3),
                    ),
                    child: Column(
                      children: [
                        Text(
                          LocalizationService.translate('vehicle_info', lang),
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 16),
                        ),
                        const SizedBox(height: 20),
                        _buildField(
                            LocalizationService.translate('model', lang),
                            _carModelController,
                            Icons.directions_car,
                            lang),
                        const SizedBox(height: 15),
                        _buildField(
                            LocalizationService.translate('plate', lang),
                            _carPlateController,
                            Icons.tag,
                            lang),
                        const SizedBox(height: 15),
                        _buildField(
                            LocalizationService.translate('color', lang),
                            _carColorController,
                            Icons.palette,
                            lang),
                        const SizedBox(height: 15),
                        _buildDropdown(vehicleTypes, lang),
                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: _isUploading ? null : _completeProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accentGold,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15)),
                              elevation: 8,
                            ),
                            child: _isUploading
                                ? const CircularProgressIndicator(
                                    color: Colors.black)
                                : Text(
                                    LocalizationService.translate(
                                        'submit_for_approval', lang),
                                    style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller,
      IconData icon, String lang) {
    return TextFormField(
      controller: controller,
      validator: (val) =>
          val!.isEmpty ? LocalizationService.translate('required', lang) : null,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: label,
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        prefixIcon: Icon(icon, color: _accentGold, size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 0),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Colors.white70, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: _accentGold, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Colors.redAccent, width: 2),
        ),
      ),
    );
  }

  Widget _buildDropdown(List<Map<String, String>> vehicleTypes, String lang) {
    bool isValid = vehicleTypes.any((t) => t['id'] == _selectedVehicleType);
    String effectiveValue = isValid ? _selectedVehicleType : 'Car';

    return DropdownButtonFormField<String>(
      value: effectiveValue,
      isExpanded: true,
      dropdownColor: const Color(0xFF4B2E0B),
      icon: Icon(Icons.arrow_drop_down, color: _accentGold),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.category, color: _accentGold, size: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 15),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Colors.white70, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: _accentGold, width: 2),
        ),
      ),
      items: vehicleTypes.map((type) {
        return DropdownMenuItem(
          value: type['id'],
          child: Center(
            child: Text(LocalizationService.translate(type['name']!, lang),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        );
      }).toList(),
      onChanged: (val) => setState(() => _selectedVehicleType = val!),
    );
  }
}
