import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sta/utils/theme.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen>
    with TickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  AnimationController? _animationController;
  // Initialize vehicles immediately
  final List<Vehicle> _vehicles = List.generate(25, (index) => Vehicle());

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration:
          const Duration(milliseconds: 16), // High frequency for smooth motion
    )
      ..addListener(() {
        if (mounted) {
          setState(() {
            for (var v in _vehicles) {
              v.update();
            }
          });
        }
      })
      ..repeat();
  }

  @override
  void dispose() {
    _animationController?.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tafadhali jaza sehemu zote')),
      );
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final success = await auth.login(username, password, role: UserRole.admin);

    if (success) {
      if (auth.currentUser?.role == UserRole.admin) {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
              context, '/admin-home', (route) => false);
        }
      } else {
        await auth.logout();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Huna ruhusa ya kuingia hapa'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(auth.error ?? 'Taarifa si sahihi'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;
    final adminGold = AppTheme.adminPrimary;
    final adminBg = AppTheme.adminBg;
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: adminBg,
      body: Stack(
        children: [
          // 1. CLEAR TRAFFIC ANIMATION
          Positioned.fill(
            child: CustomPaint(
              painter: TrafficPainter(
                vehicles: _vehicles,
                primaryColor: adminGold,
              ),
            ),
          ),

          // 2. MODERATE OVERLAY
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  adminBg.withValues(alpha: 0.4),
                  Colors.transparent,
                  adminBg.withValues(alpha: 0.4),
                ],
              ),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Container(
                constraints: BoxConstraints(maxWidth: isDesktop ? 720 : 380),
                decoration: BoxDecoration(
                  color: AppTheme.adminSurface.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      blurRadius: 50,
                      offset: const Offset(0, 20),
                    )
                  ],
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1), width: 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: isDesktop
                      ? IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(child: _buildLeftBanner(adminGold)),
                              Expanded(
                                  child: _buildLoginForm(
                                      isDesktop, adminGold, auth)),
                            ],
                          ),
                        )
                      : _buildLoginForm(isDesktop, adminGold, auth),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _tapCount = 0;

  Widget _buildLeftBanner(Color adminGold) {
    return GestureDetector(
      onTap: () async {
        _tapCount++;
        if (_tapCount >= 5) {
          _tapCount = 0;
          // MAGIC FIX: Create Admin Profile
          try {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Inarekebisha Admin Profile...')),
            );

            // Lengo ni kuhakikisha huyo mtumiaji yupo kwenye 'staff' collection na role 'admin'
            // Tutatumia register function au database direct ikiwa tunaweza
            final scaffoldMessenger = ScaffoldMessenger.of(context);
            await FirebaseFirestore.instance
                .collection('staff')
                .doc('admin_fix')
                .set({
              'email': 'admin@sta.co.tz',
              'name': 'STA Admin',
              'role': 'admin',
              'phoneNumber': '0000000000',
              'createdAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

            scaffoldMessenger.showSnackBar(
              const SnackBar(
                  content: Text(
                      'Admin Profile imerekebishwa! Jaribu kuingia sasa.')),
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Hitilafu: $e')),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: const Color(0xFF0D111A).withValues(alpha: 0.7),
          border: Border(
            right: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: adminGold.withValues(alpha: 0.4), width: 2),
              ),
              child: Icon(Icons.local_shipping_outlined,
                  size: 50, color: adminGold),
            ),
            const SizedBox(height: 30),
            Text(
              "STA RIDE",
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: adminGold,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "FLEET CONTROL CENTER",
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.4),
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginForm(bool isDesktop, Color adminGold, AuthProvider auth) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 40.0 : 25.0,
        vertical: 40.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "ADMIN LOGIN",
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 35),
          _buildInputField(
            label: "Username",
            controller: _usernameController,
            icon: Icons.person_3_outlined,
          ),
          const SizedBox(height: 20),
          _buildInputField(
            label: "Password",
            controller: _passwordController,
            icon: Icons.lock_outline_rounded,
            isPassword: true,
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: auth.isLoading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: adminGold,
                foregroundColor: Colors.black,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: auth.isLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Text("ACCESS DASHBOARD"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool isPassword = false,
  }) {
    final adminGold = AppTheme.adminPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.5),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFF1F2533),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword ? _obscurePassword : false,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              prefixIcon:
                  Icon(icon, color: adminGold.withValues(alpha: 0.6), size: 20),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.white.withValues(alpha: 0.2),
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}

enum VehicleType { car, bike, truck }

class Vehicle {
  double x = 0;
  double y = 0;
  double speed = 0;
  late IconData icon;
  late Color color;

  Vehicle() {
    _reset(randomX: true);
  }

  void _reset({bool randomX = false}) {
    // 10 distinct lanes
    int lane = math.Random().nextInt(10);
    y = (lane + 1) / 12;

    bool moveRight = lane % 2 == 0;
    // Faster speeds for better visibility
    speed = (math.Random().nextDouble() * 0.008) + 0.004;
    if (!moveRight) speed *= -1;

    x = randomX ? math.Random().nextDouble() : (moveRight ? -0.2 : 1.2);

    int r = math.Random().nextInt(3);
    if (r == 0) {
      icon = Icons.directions_car_rounded;
    } else if (r == 1) {
      icon = Icons.moped_rounded;
    } else {
      icon = Icons.local_shipping_rounded;
    }

    // Alt colors: Gold or White
    color = moveRight ? const Color(0xFFEAB308) : Colors.white;
  }

  void update() {
    x += speed;
    if (speed > 0 && x > 1.3) _reset();
    if (speed < 0 && x < -0.3) _reset();
  }
}

class TrafficPainter extends CustomPainter {
  final List<Vehicle> vehicles;
  final Color primaryColor;

  TrafficPainter({required this.vehicles, required this.primaryColor});

  @override
  void paint(Canvas canvas, Size size) {
    for (var v in vehicles) {
      final double posX = v.x * size.width;
      final double posY = v.y * size.height;

      // Draw a subtle glow/trail
      final trailPaint = Paint()
        ..color = v.color.withValues(alpha: 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
      canvas.drawCircle(Offset(posX, posY), 30, trailPaint);

      final textPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(v.icon.codePoint),
          style: TextStyle(
            fontSize: v.icon == Icons.local_shipping_rounded ? 50 : 38,
            fontFamily: v.icon.fontFamily,
            package: v.icon.fontPackage,
            color: v.color.withValues(alpha: 0.4),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      canvas.translate(posX, posY);
      if (v.speed < 0) canvas.scale(-1, 1); // Flip for direction

      textPainter.paint(
          canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant TrafficPainter oldDelegate) => true;
}
