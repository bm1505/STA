import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import '../utils/theme.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  final Color _bgBrown = const Color(0xFF2B2B2B);
  final Color _accentGold = AppTheme.primaryGold;

  Future<void> _handleAuth() async {
    final identifier = _phoneController.text.trim();
    if (identifier.isEmpty || _passwordController.text.isEmpty) {
      _showSnackBar("Tafadhali jaza nafasi zote", Colors.redAccent);
      return;
    }

    setState(() => _isLoading = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final success = await authProvider.login(
      identifier,
      _passwordController.text.trim(),
      role: UserRole.rider,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      final user = authProvider.currentUser;
      if (user != null) {
        if (!user.isProfileComplete) {
          Navigator.pushReplacementNamed(context, '/profile');
        } else {
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } else {
      _showSnackBar(
          authProvider.error ?? "Ingia imeshindikana", Colors.redAccent);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Container(
                        height: 100,
                        width: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            )
                          ],
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
                      Container(
                        padding: const EdgeInsets.all(25),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(color: Colors.black, width: 3),
                        ),
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
                            _buildOutlineField(
                              hint: "Enter username",
                              controller: _phoneController,
                              icon: Icons.person_outline,
                            ),
                            const SizedBox(height: 20),
                            _buildOutlineField(
                              hint: "Enter password",
                              controller: _passwordController,
                              icon: Icons.lock_outline,
                              isPassword: true,
                            ),
                            const SizedBox(height: 30),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildSmallButton(
                                    label: "Login",
                                    onTap: _isLoading ? null : _handleAuth,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildSmallButton(
                                    label: "Google",
                                    onTap: () {},
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 25),
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ForgotPasswordScreen(
                                            initialEmail: _phoneController.text.trim(),
                                          ),
                                        ),
                                      );
                                    },
                                    child: const Text(
                                      "Forgot password",
                                      style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pushNamed(context, '/register');
                                    },
                                    child: Text(
                                      "Register Account",
                                      style: TextStyle(
                                          color: _accentGold,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildOutlineField({
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    bool isPassword = false,
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
        obscureText: isPassword,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 15, right: 10),
            child: Icon(icon, color: _accentGold.withValues(alpha: 0.7), size: 22),
          ),
          hintText: hint,
          hintStyle: const TextStyle(
            color: Colors.white38,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
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
                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
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
