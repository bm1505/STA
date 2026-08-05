import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sta/providers/auth_provider.dart';
import 'package:sta/models/user.dart';
import 'package:sta/services/localization_service.dart';
import '../utils/theme.dart';
import 'forgot_password_screen.dart';

class DriverAuthScreen extends StatefulWidget {
  const DriverAuthScreen({super.key});

  @override
  State<DriverAuthScreen> createState() => _DriverAuthScreenState();
}

class _DriverAuthScreenState extends State<DriverAuthScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  final _formKey = GlobalKey<FormState>();

  // Colors based on LoginScreen
  final Color _bgBrown = const Color(0xFF2B2B2B);
  final Color _accentGold = AppTheme.primaryGold;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    if (!_formKey.currentState!.validate()) return;

    final identifier = _phoneController.text.trim();
    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final success = await authProvider.login(
      identifier,
      _passwordController.text.trim(),
      role: UserRole.driver,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      final user = authProvider.currentUser;
      if (user != null) {
        if (user.isProfileComplete && user.carModel != null) {
          Navigator.pushReplacementNamed(context, '/driver-home');
        } else {
          Navigator.pushReplacementNamed(context, '/driver-setup',
              arguments: user.id);
        }
      }
    } else {
      final lang = authProvider.language;
      _showSnackBar(
          authProvider.error ??
              LocalizationService.translate('login_failed', lang),
          Colors.redAccent);
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
                  child: Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      final lang = auth.language;
                      return Form(
                        key: _formKey,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 40),
                            // Logo (Driver Icon)
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
                                  image: AssetImage('assets/driver_icon.png'),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              "STA DRIVER",
                              style: GoogleFonts.poppins(
                                color: _accentGold,
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 40),

                            // Login Container
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
                                    LocalizationService.translate(
                                        'login_to_account', lang),
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 25),

                                  // Phone Field
                                  _buildOutlineField(
                                    hint: LocalizationService.translate(
                                        'email_or_phone', lang),
                                    controller: _phoneController,
                                    icon: Icons.person_outline,
                                  ),
                                  const SizedBox(height: 20),

                                  // Password Field
                                  _buildOutlineField(
                                    hint: LocalizationService.translate(
                                        'password', lang),
                                    controller: _passwordController,
                                    icon: Icons.lock_outline,
                                    isPassword: true,
                                  ),
                                  const SizedBox(height: 30),

                                  // Buttons Row
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildSmallButton(
                                          label: LocalizationService.translate(
                                              'login_btn', lang),
                                          onTap: _isLoading ? null : _handleAuth,
                                          isLoading: _isLoading,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildSmallButton(
                                          label: LocalizationService.translate(
                                              'continue_google', lang),
                                          onTap: _isLoading
                                              ? null
                                              : () async {
                                                  setState(() => _isLoading = true);
                                                  final auth =
                                                      Provider.of<AuthProvider>(
                                                          context,
                                                          listen: false);
                                                  final result =
                                                      await auth.signInWithGoogle(
                                                          UserRole.driver);

                                                  if (!context.mounted) return;
                                                  setState(() => _isLoading = false);

                                                  if (result['success']) {
                                                    final user = auth.currentUser;
                                                    if (user != null) {
                                                      if (!context.mounted) return;
                                                      if (user.isProfileComplete &&
                                                          user.carModel != null) {
                                                        Navigator
                                                            .pushReplacementNamed(
                                                                context,
                                                                '/driver-home');
                                                      } else {
                                                        Navigator
                                                            .pushReplacementNamed(
                                                                context,
                                                                '/driver-setup',
                                                                arguments: user.id);
                                                      }
                                                    }
                                                  } else {
                                                    _showSnackBar(
                                                        result['error'] ??
                                                            LocalizationService.translate(
                                                                'google_login_failed',
                                                                lang),
                                                        Colors.redAccent);
                                                  }
                                                },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 25),

                                  // Bottom Links
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            TextButton(
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        ForgotPasswordScreen(
                                                      initialEmail: _phoneController
                                                          .text
                                                          .trim(),
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: Text(
                                                LocalizationService.translate(
                                                    'forgot_password', lang),
                                                style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w900),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                Navigator.pushNamed(
                                                    context, '/driver-register-flow');
                                              },
                                              child: Text(
                                                LocalizationService.translate(
                                                    'signup_link', lang),
                                                style: TextStyle(
                                                    color: _accentGold,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w900),
                                              ),
                                            ),
                                          ],
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
                      );
                    },
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
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.black, width: 2.5),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 15,
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return ''; // Empty return to avoid ugly error text in this style
          }
          return null;
        },
        decoration: InputDecoration(
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 15, right: 10),
            child:
                Icon(icon, color: _accentGold.withValues(alpha: 0.7), size: 22),
          ),
          hintText: hint,
          hintStyle: const TextStyle(
            color: Colors.white38,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          border: InputBorder.none,
          errorStyle: const TextStyle(height: 0),
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  Widget _buildSmallButton(
      {required String label, VoidCallback? onTap, bool isLoading = false}) {
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
        child: isLoading
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
