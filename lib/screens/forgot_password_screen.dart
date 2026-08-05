import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../utils/theme.dart';
import 'reset_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late TextEditingController _emailController;
  bool _isLoading = false;

  final Color _bgBrown = const Color(0xFF2B2B2B);
  final Color _accentGold = AppTheme.primaryGold;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  Future<void> _handleSubmit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Tafadhali ingiza barua pepe au namba ya simu")),
      );
      return;
    }

    setState(() => _isLoading = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Call forgot password to send OTP/Email
    final result = await authProvider.forgotPassword(email);

    if (mounted) {
      setState(() => _isLoading = false);
      if (result['success']) {
        // Kila mara sasa tunaenda kwenye ResetPasswordScreen (OTP)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ResetPasswordScreen(identifier: email),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? "Imeshindikana kutuma ombi"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBrown,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [
              Color(0xFF7A4B13),
              Color(0xFF4B2E0B),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              children: [
                const SizedBox(height: 40),
                // Back Button
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 20),
                // Logo
                Container(
                  height: 80,
                  width: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    image: const DecorationImage(
                      image: AssetImage('assets/rider_icon.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "STA RIDE",
                  style: GoogleFonts.poppins(
                    color: _accentGold,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 40),

                // Recovery Container
                Container(
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: Colors.black, width: 3),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "Recovery",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 15),
                      const Text(
                        "Ingiza barua pepe au namba ya simu.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 30),

                      // Input Field
                      _buildOutlineField(
                        hint: "Enter Email / Phone",
                        controller: _emailController,
                        icon: Icons.person_outline,
                      ),
                      const SizedBox(height: 30),

                      // Send Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleSubmit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentGold,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(
                                  color: Colors.black, width: 2),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.black, strokeWidth: 2))
                              : Text(
                                  "RESET PASSWORD",
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
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
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2B2B2B),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.black, width: 2)),
        title: Text("Imekamilika",
            style: GoogleFonts.poppins(
                color: _accentGold, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Funga dialog
              Navigator.pop(context); // Rudi kwenye Login
            },
            child: Text("SAWA",
                style:
                    TextStyle(color: _accentGold, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildOutlineField({
    required String hint,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return Container(
      height: 55,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.black, width: 2.5),
      ),
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15),
        decoration: InputDecoration(
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 15),
            child:
                Icon(icon, color: _accentGold.withValues(alpha: 0.7), size: 22),
          ),
          hintText: hint,
          hintStyle: const TextStyle(
              color: Colors.white38, fontSize: 14, fontWeight: FontWeight.w700),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }
}
