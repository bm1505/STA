import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';
import '../models/user.dart';
import '../services/database_service.dart';
import '../utils/theme.dart';

class VerifyOtpScreen extends StatefulWidget {
  final String identifier;
  const VerifyOtpScreen({super.key, required this.identifier});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  int _resendTimer = 5;
  Timer? _timer;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startTimer() {
    setState(() {
      _resendTimer = 5;
      _canResend = false;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendTimer > 0) {
        setState(() => _resendTimer--);
      } else {
        setState(() => _canResend = true);
        _timer?.cancel();
      }
    });
  }

  Future<void> _handleResendOtp() async {
    if (!_canResend) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.resendOtp(widget.identifier);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(LocalizationService.translate(
                  'otp_resent', authProvider.language))),
        );
        _startTimer();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to resend OTP'),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _handleVerify() async {
    final lang = Provider.of<AuthProvider>(context, listen: false).language;

    if (_otpController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(LocalizationService.translate('invalid_otp', lang))),
      );
      return;
    }

    setState(() => _isLoading = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final success = await authProvider.verifyOtp(
      widget.identifier,
      _otpController.text.trim(),
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        final user = authProvider.currentUser;

        // Mark user as verified in Firestore if not already
        if (user != null && !user.isVerified) {
          final verifiedUser = user.copyWith(isVerified: true);
          await authProvider.updateProfile(); // This saves session and syncs to DB
          // Wait, updateProfile might not be enough if it doesn't set isVerified specifically.
          // Let's ensure DatabaseService.instance.saveUser is called with isVerified=true.
          await DatabaseService.instance.saveUser(verifiedUser);
          await authProvider.checkAuthStatus(); // Refresh local state
        }

        if (user?.role == UserRole.driver) {
          Navigator.pushNamedAndRemoveUntil(
              context, '/driver-home', (route) => false);
        } else if (user?.role == UserRole.admin) {
          Navigator.pushNamedAndRemoveUntil(
              context, '/admin-home', (route) => false);
        } else {
          Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(authProvider.error ?? "Verification failed"),
              backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  final Color _bgBrown = const Color(0xFF2B2B2B);
  final Color _accentGold = AppTheme.primaryGold;

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AuthProvider>(context).language;

    return Scaffold(
      backgroundColor: _bgBrown,
      appBar: AppBar(
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
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              children: [
                const SizedBox(height: 30),
                // Icon
                Container(
                  height: 80,
                  width: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.black, width: 2.5),
                  ),
                  child:
                      const Icon(Icons.security, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 25),
                Text(
                  LocalizationService.translate('verify_account', lang),
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    "${LocalizationService.translate('enter_otp_desc', lang)} ${widget.identifier}",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        color: Colors.white70, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 40),

                // OTP Box
                Container(
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: Colors.black, width: 3),
                  ),
                  child: Column(
                    children: [
                      _buildInputField(
                          LocalizationService.translate('otp_code', lang),
                          _otpController,
                          Icons.vibration,
                          keyboardType: TextInputType.number),
                      const SizedBox(height: 30),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleVerify,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentGold,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                              side: const BorderSide(
                                  color: Colors.black, width: 2.5),
                            ),
                            elevation: 8,
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.black)
                              : Text(
                                  LocalizationService.translate('verify', lang),
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                        ),
                      ),
                      const SizedBox(height: 25),
                      Center(
                        child: _canResend
                            ? TextButton(
                                onPressed: _handleResendOtp,
                                child: Text(
                                  LocalizationService.translate(
                                      'resend_otp', lang),
                                  style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.underline),
                                ),
                              )
                            : Text(
                                "${LocalizationService.translate('resend_in', lang)} $_resendTimer s",
                                style: const TextStyle(
                                    color: Colors.white60, fontSize: 13),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField(
      String label, TextEditingController controller, IconData icon,
      {bool isPassword = false,
      TextInputType keyboardType = TextInputType.text}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: keyboardType,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 8),
        textAlign: TextAlign.center,
        maxLength: 6,
        decoration: const InputDecoration(
          hintText: "• • • • • •",
          hintStyle: TextStyle(color: Colors.white24, letterSpacing: 8),
          counterText: "",
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
    );
  }
}
