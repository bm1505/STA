import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';

import '../utils/theme.dart';
import 'register_screen.dart';

import 'forgot_password_screen.dart';

class AuthOptionScreen extends StatefulWidget {
  const AuthOptionScreen({super.key});

  @override
  State<AuthOptionScreen> createState() => _AuthOptionScreenState();
}

class _AuthOptionScreenState extends State<AuthOptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  // Rangi kutoka kwenye picha yako
  final Color _bgBrown = const Color(0xFF2B2B2B);
  final Color _accentGold = AppTheme.primaryGold;

  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.login(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (success) {
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.error ?? "Login Failed"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final result = await auth.signInWithGoogle(UserRole.rider);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      Navigator.pushReplacementNamed(context, '/home');
    } else if (result['error'] != 'Sign in cancelled') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'] ?? "Google Sign-In Failed")),
      );
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
                const SizedBox(height: 60),
                // Logo (Green Icon)
                Container(
                  height: 100,
                  width: 100,
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
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 40),

                // Login Box
                Container(
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: Colors.black, width: 3),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        Text(
                          "Login here",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 25),

                        // Username Field
                        _buildOutlineField(
                          hint: "Enter username",
                          controller: _emailController,
                        ),
                        const SizedBox(height: 20),

                        // Password Field
                        _buildOutlineField(
                          hint: "Enter password",
                          controller: _passwordController,
                          isPassword: true,
                        ),
                        const SizedBox(height: 30),

                        // Buttons Row
                        Row(
                          children: [
                            Expanded(
                              child: _buildSmallButton(
                                label: "Login",
                                onTap: _isLoading ? null : _handleLogin,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildSmallButton(
                                label: "Google",
                                onTap: _isLoading ? null : _handleGoogleSignIn,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 25),

                        // Bottom Links
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ForgotPasswordScreen(
                                      initialEmail:
                                          _emailController.text.trim(),
                                    ),
                                  ),
                                );
                              },
                              child: const Text(
                                "Forgot password",
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          const RegisterScreen()),
                                );
                              },
                              child: Text(
                                "Register Account",
                                style: TextStyle(
                                    color: _accentGold,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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

  Widget _buildOutlineField({
    required String hint,
    required TextEditingController controller,
    bool isPassword = false,
  }) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword,
        textAlign: TextAlign.center,
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
              color: Colors.white38, fontSize: 14, fontWeight: FontWeight.w900),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        validator: (value) => value == null || value.isEmpty ? "" : null,
      ),
    );
  }

  Widget _buildSmallButton({required String label, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 45,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _accentGold,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: _isLoading && label == "Login"
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    color: Colors.black, strokeWidth: 2),
              )
            : Text(
                label,
                style: GoogleFonts.poppins(
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
      ),
    );
  }
}
