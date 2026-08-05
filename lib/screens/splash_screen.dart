import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../utils/theme.dart';
import '../models/user.dart';

class SplashScreen extends StatefulWidget {
  final UserRole? role;
  const SplashScreen({super.key, this.role});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _requestController;
  late AnimationController _moveController;
  late AnimationController _finalController;
  late AnimationController _shimmerController;
  late AnimationController _pulseController;
  late AnimationController _roadController;
  
  late Animation<double> _buttonSlideAnimation;
  late Animation<double> _buttonPulseAnimation;
  
  final List<Offset> _particles = List.generate(20, (index) => Offset(math.Random().nextDouble(), math.Random().nextDouble()));
  
  int _animationPhase = 0; // 0: Requesting, 1: Moving, 2: Logo Reveal, 3: Ready

  @override
  void initState() {
    super.initState();
    
    _requestController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _moveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _finalController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _buttonSlideAnimation = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(parent: _finalController, curve: Curves.easeOutBack),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _buttonPulseAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _roadController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();

    _startAnimationSequence();
  }

  void _startAnimationSequence() async {
    // Stage 1: Requesting (Realistic Hand)
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;
    setState(() => _animationPhase = 1);
    
    // Stage 2: Moving (Road Perspective)
    _moveController.forward();
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;
    setState(() => _animationPhase = 2);
    
    // Stage 3: Logo Reveal
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    setState(() => _animationPhase = 3);
    
    _finalController.forward().then((_) {
      _pulseController.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _requestController.dispose();
    _moveController.dispose();
    _finalController.dispose();
    _shimmerController.dispose();
    _pulseController.dispose();
    _roadController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Subtle Stardust Background
          Positioned.fill(
            child: Opacity(
              opacity: 0.03,
              child: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage("https://www.transparenttextures.com/patterns/stardust.png"),
                    repeat: ImageRepeat.repeat,
                  ),
                ),
              ),
            ),
          ),
          
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              child: _buildCurrentPhase(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPhase() {
    switch (_animationPhase) {
      case 0: return _buildRequestingPhase();
      case 1: return _buildMovingPhase();
      case 2: return _buildLogoPhase();
      default: return _buildFinalPhase();
    }
  }

  // PHASE 0: MODERN RADAR SEARCH
  Widget _buildRequestingPhase() {
    return Stack(
      key: const ValueKey(0),
      alignment: Alignment.center,
      children: [
        // Pulsing background rings with blur
        ...List.generate(4, (index) {
          return AnimatedBuilder(
            animation: _requestController,
            builder: (context, child) {
              double progress = (_requestController.value + (index * 0.25)) % 1.0;
              return Opacity(
                opacity: (1.0 - progress) * 0.5,
                child: Container(
                  width: 100 + (progress * 400),
                  height: 100 + (progress * 400),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primaryGold,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryGold.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 10,
                      )
                    ],
                  ),
                ),
              );
            },
          );
        }),
        
        // Rotating Scanning Line
        AnimatedBuilder(
          animation: _requestController,
          builder: (context, child) {
            return Transform.rotate(
              angle: _requestController.value * 2 * math.pi,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    center: Alignment.center,
                    startAngle: 0.0,
                    endAngle: math.pi / 2,
                    colors: [
                      AppTheme.primaryGold.withOpacity(0.5),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            );
          },
        ),

        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                // Inner glowing core
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryGold, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryGold.withOpacity(0.4),
                        blurRadius: 30,
                      )
                    ],
                  ),
                  child: Icon(Icons.location_searching_rounded, 
                    color: AppTheme.primaryGold, size: 35),
                ),
              ],
            ),
            const SizedBox(height: 60),
            Shimmer.fromColors(
              baseColor: AppTheme.primaryGold,
              highlightColor: Colors.white,
              child: Text(
                "CONNECTING TO NETWORK",
                style: GoogleFonts.poppins(
                  color: AppTheme.primaryGold,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // PHASE 1: MODERN VELOCITY STREAKS
  Widget _buildMovingPhase() {
    return Container(
      key: const ValueKey(1),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Moving Streaks (Velocity Effect)
          ...List.generate(20, (index) {
            final random = math.Random(index);
            final angle = random.nextDouble() * 2 * math.pi;
            return AnimatedBuilder(
              animation: _moveController,
              builder: (context, child) {
                double p = (_moveController.value + (index / 20)) % 1.0;
                double distance = 50 + (p * 500);
                return Transform.translate(
                  offset: Offset(
                    math.cos(angle) * distance,
                    math.sin(angle) * distance,
                  ),
                  child: Container(
                    width: 2 + (p * 4),
                    height: 20 + (p * 100),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppTheme.primaryGold.withOpacity(1 - p),
                          Colors.transparent,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              },
            );
          }),

          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _moveController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 0.8 + (_moveController.value * 0.4),
                    child: Opacity(
                      opacity: _moveController.value,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryGold.withOpacity(0.3),
                              blurRadius: 50,
                              spreadRadius: 10,
                            )
                          ],
                        ),
                        child: Icon(
                          Icons.auto_awesome_motion_rounded,
                          color: AppTheme.primaryGold,
                          size: 80,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
              Text(
                "PREPARING LUXURY",
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // PHASE 2: LOGO REVEAL
  Widget _buildLogoPhase() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Gold Particles
        ..._particles.map((offset) {
          return AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(
                  (offset.dx - 0.5) * 400 * _shimmerController.value,
                  (offset.dy - 0.5) * 400 * _shimmerController.value,
                ),
                child: Opacity(
                  opacity: 1 - _shimmerController.value,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(color: AppTheme.primaryGold, shape: BoxShape.circle),
                  ),
                ),
              );
            },
          );
        }),
        Column(
          key: const ValueKey(2),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLogoWidget(),
            const SizedBox(height: 30),
            Text(
              widget.role == UserRole.driver ? "STA DRIVER" : "STA RIDE",
              style: GoogleFonts.poppins(
                color: AppTheme.primaryGold,
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: 8,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFinalPhase() {
    return Container(
      key: const ValueKey(3),
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.5,
          colors: [
            const Color(0xFF1A1A1A),
            Colors.black,
            AppTheme.primaryGold.withOpacity(0.05),
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Subtle Floating Particles in background
          ..._particles.take(15).map((offset) {
            return AnimatedBuilder(
              animation: _shimmerController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(
                    (offset.dx - 0.5) * 600,
                    (offset.dy - 0.5) * 1000 + (math.sin(_shimmerController.value * math.pi * 2 + offset.dx * 10) * 40),
                  ),
                  child: Opacity(
                    opacity: 0.3,
                    child: Container(
                      width: 2 + offset.dx * 3,
                      height: 2 + offset.dx * 3,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGold,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryGold.withOpacity(0.5),
                            blurRadius: 5,
                          )
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          }),
          
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLogoWidget(),
              const SizedBox(height: 30),
              Text(
                widget.role == UserRole.driver ? "STA DRIVER" : "STA RIDE",
                style: GoogleFonts.poppins(
                  color: AppTheme.primaryGold,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 10,
                  shadows: [
                    Shadow(color: AppTheme.primaryGold.withOpacity(0.3), blurRadius: 20)
                  ],
                ),
              ),
              const SizedBox(height: 80),
              AnimatedBuilder(
                animation: Listenable.merge([_finalController, _pulseController]),
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(0, _buttonSlideAnimation.value),
                    child: Transform.scale(
                      scale: _buttonPulseAnimation.value,
                      child: Opacity(
                        opacity: _finalController.value,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.heavyImpact();
                              Navigator.pushReplacementNamed(context, '/');
                            },
                            child: Container(
                              height: 70,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppTheme.primaryGold,
                                    const Color(0xFFFFB300),
                                    AppTheme.primaryGold.withOpacity(0.8),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(25),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.primaryGold.withOpacity(0.4 * _buttonPulseAnimation.value),
                                    blurRadius: 30 * _buttonPulseAnimation.value,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 10),
                                  )
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Shimmer.fromColors(
                                    baseColor: Colors.black,
                                    highlightColor: Colors.white.withOpacity(0.6),
                                    period: const Duration(seconds: 2),
                                    child: Text("START NOW", style: GoogleFonts.poppins(
                                      color: Colors.black, 
                                      fontWeight: FontWeight.w900, 
                                      letterSpacing: 3.0,
                                      fontSize: 18,
                                    )),
                                  ),
                                  const SizedBox(width: 20),
                                  const Icon(Icons.arrow_forward_rounded, size: 24, color: Colors.black),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogoWidget() {
    return Container(
      height: 150, width: 150,
      decoration: BoxDecoration(
        color: AppTheme.primaryGold,
        borderRadius: BorderRadius.circular(45),
        boxShadow: [BoxShadow(color: AppTheme.primaryGold.withOpacity(0.3), blurRadius: 40)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(45),
        child: Stack(
          children: [
            Center(child: Icon(
              widget.role == UserRole.driver ? Icons.local_taxi_rounded : Icons.directions_car_rounded,
              size: 90, color: Colors.black,
            )),
            AnimatedBuilder(
              animation: _shimmerController,
              builder: (context, _) => Transform.translate(
                offset: Offset(-150 + (300 * _shimmerController.value), 0),
                child: Transform.rotate(
                  angle: 0.5,
                  child: Container(width: 50, height: 300, color: Colors.white.withOpacity(0.4)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RoadPainter extends CustomPainter {
  final double progress;
  RoadPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(size.width * 0.4, 0); 
    path.lineTo(size.width * 0.6, 0);
    path.lineTo(size.width * 1.2, size.height); 
    path.lineTo(-size.width * 0.2, size.height); 
    path.close();

    canvas.drawPath(path, paint);

    // Side lines
    final sidePaint = Paint()
      ..color = AppTheme.primaryGold.withValues(alpha: 0.4)
      ..strokeWidth = 3;
    canvas.drawLine(Offset(size.width * 0.4, 0), Offset(-size.width * 0.1, size.height), sidePaint);
    canvas.drawLine(Offset(size.width * 0.6, 0), Offset(size.width * 1.1, size.height), sidePaint);

    // Center dashed line
    final dashPaint = Paint()
      ..color = AppTheme.primaryGold.withValues(alpha: 0.6)
      ..strokeWidth = 4;
    
    double dashHeight = 40;
    double dashSpace = 30;
    double totalDashHeight = dashHeight + dashSpace;

    for (double i = -totalDashHeight; i < size.height; i += totalDashHeight) {
      double y = i + (progress * totalDashHeight);
      if (y > size.height) continue;
      
      // Calculate perspective width for the dash
      double perspectiveY = y / size.height;
      double width = 2 + (perspectiveY * 10);
      dashPaint.strokeWidth = width;

      double startY = math.max(0, y);
      double endY = math.min(size.height, y + dashHeight);
      
      if (startY < endY) {
        canvas.drawLine(
          Offset(size.width * 0.5, startY),
          Offset(size.width * 0.5, endY),
          dashPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(RoadPainter oldDelegate) => oldDelegate.progress != progress;
}
