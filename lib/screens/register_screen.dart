import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import '../utils/theme.dart';
import 'package:intl/intl.dart';
import 'verify_otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _dobController = TextEditingController();

  String? _selectedGender;
  bool _isLoading = false;

  final Color _bgBrown = const Color(0xFF2B2B2B);
  final Color _accentGold = AppTheme.primaryGold;

  Future<void> _handleRegister() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedGender == null) {
        _showSnackBar("Tafadhali chagua jinsia", Colors.orange);
        return;
      }
      if (_dobController.text.isEmpty) {
        _showSnackBar("Tafadhali weka tarehe ya kuzaliwa", Colors.orange);
        return;
      }

      if (_passwordController.text != _confirmPasswordController.text) {
        _showSnackBar("Nenosiri hazilingani", Colors.red);
        return;
      }

      setState(() => _isLoading = true);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      final result = await authProvider.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        role: UserRole.rider,
        gender: _selectedGender,
        dob: _dobController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result['success'] == true) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => VerifyOtpScreen(identifier: _emailController.text.trim()),
          ),
        );
      } else {
        _showSnackBar(result['error'] ?? "Usajili umeshindikana", Colors.red);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _selectDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 6570)),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _bgBrown,
              onPrimary: Colors.white,
              onSurface: _bgBrown,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dobController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
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
            colors: [Color(0xFF7A4B13), Color(0xFF4B2E0B)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Container(
                        height: 80,
                        width: 80,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            )
                          ],
                          image: const DecorationImage(
                            image: AssetImage('assets/rider_icon.png'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        "STA RIDE",
                        style: GoogleFonts.poppins(
                          color: _accentGold,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 30),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(color: Colors.black, width: 3),
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              Text(
                                "Register Account",
                                style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 20),
                              _buildOutlineField(
                                hint: "Enter Full Name",
                                controller: _nameController,
                                validator: (v) => v!.isEmpty ? "Weka jina" : null,
                              ),
                              const SizedBox(height: 12),
                              _buildOutlineField(
                                hint: "Enter Valid Email",
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                validator: (v) =>
                                    !v!.contains("@") ? "Barua pepe si sahihi" : null,
                              ),
                              const SizedBox(height: 12),
                              _buildOutlineField(
                                hint: "Enter Valid phone number",
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                validator: (v) =>
                                    v!.length < 10 ? "Namba haijakamilika" : null,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _buildGenderDropdown()),
                                  const SizedBox(width: 10),
                                  Expanded(child: _buildDateField()),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildOutlineField(
                                      hint: "Create password",
                                      controller: _passwordController,
                                      isPassword: true,
                                      validator: (v) =>
                                          v!.length < 6 ? "Herufi 6+" : null,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildOutlineField(
                                      hint: "Confirm password",
                                      controller: _confirmPasswordController,
                                      isPassword: true,
                                      validator: (v) =>
                                          v!.isEmpty ? "Thibitisha" : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 25),
                              Row(
                                children: [
                                  Expanded(
                                      child: _buildSmallButton(
                                          label: "Register",
                                          onTap:
                                              _isLoading ? null : _handleRegister)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: _buildSmallButton(
                                          label: "Google",
                                          onTap: () {
                                            Provider.of<AuthProvider>(context,
                                                    listen: false)
                                                .signInWithGoogle(UserRole.rider);
                                          })),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Already Registered?",
                                      style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900)),
                                  GestureDetector(
                                    onTap: () => Navigator.pop(context),
                                    child: Text("Login here",
                                        style: TextStyle(
                                            color: _accentGold,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900)),
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
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword,
      textAlign: TextAlign.center,
      style: const TextStyle(
          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900),
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            color: Colors.white38, fontSize: 13, fontWeight: FontWeight.w900),
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 0),
        errorStyle: const TextStyle(fontSize: 10, height: 0.8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: Colors.black, width: 2),
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
        fillColor: Colors.black26,
        filled: true,
      ),
    );
  }

  Widget _buildGenderDropdown() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedGender,
          dropdownColor: Colors.black,
          hint: const Text("Gender",
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  fontWeight: FontWeight.w900)),
          isExpanded: true,
          items: ["Male", "Female"].map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900)),
            );
          }).toList(),
          onChanged: (val) => setState(() => _selectedGender = val),
        ),
      ),
    );
  }

  Widget _buildDateField() {
    return GestureDetector(
      onTap: _selectDate,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.black, width: 2),
        ),
        child: Text(
          _dobController.text.isEmpty ? "DD/MM/YYYY" : _dobController.text,
          style: const TextStyle(
              color: Colors.white38, fontSize: 13, fontWeight: FontWeight.w900),
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
        child: _isLoading && label == "Register"
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    color: Colors.black, strokeWidth: 2))
            : Text(
                label,
                style: GoogleFonts.poppins(
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    fontSize: 15),
              ),
      ),
    );
  }
}
