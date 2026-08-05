import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../utils/theme.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String identifier;
  const ResetPasswordScreen({super.key, required this.identifier});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isLoading = false;
  bool _isOtpVerified = false; // Hii itatusaidia "kufungua" sehemu ya password

  final Color _bgBrown = const Color(0xFF2B1B06);
  final Color _accentGold = AppTheme.primaryGold;

  // 1. Uhakiki wa OTP
  Future<void> _handleVerifyOtp() async {
    if (_otpController.text.length < 6) {
      _showSnackBar("Tafadhali ingiza kodi ya OTP ya tarakimu 6");
      return;
    }

    setState(() => _isLoading = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    final isValid = await authProvider.verifyOtp(widget.identifier, _otpController.text.trim());

    setState(() => _isLoading = false);
    if (isValid) {
      setState(() => _isOtpVerified = true); // "Fungua" sehemu ya password
      _showSnackBar("OTP Imethibitishwa! Sasa weka nenosiri jipya.", isError: false);
    } else {
      _showSnackBar("Kodi ya OTP siyo sahihi. Tafadhali jaribu tena.");
    }
  }

  // 2. Kuhifadhi Nenosiri Jipya
  Future<void> _handleSaveNewPassword() async {
    if (_newPasswordController.text.length < 6) {
      _showSnackBar("Nenosiri lazima liwe na herufi zisizopungua 6");
      return;
    }
    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showSnackBar("Nenosiri halifanani");
      return;
    }

    setState(() => _isLoading = true);
    // Hapa nenosiri jipya lingehifadhiwa kwenye Firebase. 
    // Kwa sasa tunasimulate mafanikio ya uhakiki.
    await Future.delayed(const Duration(seconds: 2)); 

    if (mounted) {
      setState(() => _isLoading = false);
      _showSuccessDialog();
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _accentGold, width: 2),
        ),
        title: Icon(Icons.check_circle, color: _accentGold, size: 60),
        content: const Text(
          "Nenosiri lako limebadilishwa kikamilifu! Sasa unaweza kuingia kwenye akaunti yako.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
              style: ElevatedButton.styleFrom(backgroundColor: _accentGold),
              child: const Text("INGIA SASA", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBrown,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF4B2E0B), Color(0xFF1A0F02)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 10),
                // Logo
                Container(
                  height: 90,
                  width: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    image: const DecorationImage(
                      image: AssetImage('assets/rider_icon.png'),
                      fit: BoxFit.cover,
                    ),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _isOtpVerified ? "NEW PASSWORD" : "VERIFY OTP",
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: _accentGold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _isOtpVerified 
                    ? "Tafadhali weka nenosiri lako jipya la siri."
                    : "Tumetuma kodi ya siri kwenye ${_maskEmail(widget.identifier)}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 40),

                if (!_isOtpVerified) ...[
                  // SEHEMU YA OTP
                  _buildStyledField(
                    hint: "Kodi ya OTP (6 digits)",
                    controller: _otpController,
                    icon: Icons.security,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 40),
                  _buildActionButton("THIBITISHA OTP", _handleVerifyOtp),
                ] else ...[
                  // SEHEMU YA PASSWORD MPYA (Hii inafunguka baada ya OTP)
                  _buildStyledField(
                    hint: "Nenosiri Jipya",
                    controller: _newPasswordController,
                    icon: Icons.lock_outline,
                    isPassword: true,
                  ),
                  const SizedBox(height: 20),
                  _buildStyledField(
                    hint: "Rudia Nenosiri",
                    controller: _confirmPasswordController,
                    icon: Icons.lock_reset,
                    isPassword: true,
                  ),
                  const SizedBox(height: 40),
                  _buildActionButton("HIFADHI NENOSIRI", _handleSaveNewPassword),
                ],
                
                const SizedBox(height: 30),
                if (!_isOtpVerified)
                  TextButton(
                    onPressed: _isLoading ? null : () => Provider.of<AuthProvider>(context, listen: false).resendOtp(widget.identifier),
                    child: Text("Tuma tena kodi ya OTP", style: TextStyle(color: _accentGold, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _maskEmail(String email) {
    if (!email.contains('@')) return email;
    final parts = email.split('@');
    return "${parts[0].substring(0, 3)}***@${parts[1]}";
  }

  Widget _buildActionButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentGold,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: const BorderSide(color: Colors.black, width: 2),
          ),
          elevation: 5,
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.black)
            : Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 18)),
      ),
    );
  }

  Widget _buildStyledField({
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: keyboardType,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: _accentGold, size: 24),
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 16),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }
}
