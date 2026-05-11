import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _seqController;
  late AnimationController _pulseController;
  late AnimationController _orbController;

  late Animation<double> _bgFade;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _ringScale;
  late Animation<double> _ringOpacity;
  late Animation<double> _titleOpacity;
  late Animation<Offset> _titleSlide;
  late Animation<double> _subtitleOpacity;
  late Animation<double> _badgeOpacity;
  late Animation<Offset> _badgeSlide;
  late Animation<double> _loaderOpacity;
  late Animation<double> _footerOpacity;
  late Animation<double> _pulseScale;
  late Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();

    _seqController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _bgFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _seqController,
        curve: const Interval(0.0, 0.15, curve: Curves.easeOut),
      ),
    );
    _logoOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _seqController,
        curve: const Interval(0.08, 0.25, curve: Curves.easeOut),
      ),
    );
    _logoScale = Tween(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _seqController,
        curve: const Interval(0.08, 0.30, curve: Curves.elasticOut),
      ),
    );
    _ringScale = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _seqController,
        curve: const Interval(0.20, 0.40, curve: Curves.easeOut),
      ),
    );
    _ringOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _seqController,
        curve: const Interval(0.20, 0.35, curve: Curves.easeOut),
      ),
    );
    _titleOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _seqController,
        curve: const Interval(0.30, 0.48, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _seqController,
        curve: const Interval(0.30, 0.50, curve: Curves.easeOut),
      ),
    );
    _subtitleOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _seqController,
        curve: const Interval(0.42, 0.58, curve: Curves.easeOut),
      ),
    );
    _badgeOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _seqController,
        curve: const Interval(0.52, 0.68, curve: Curves.easeOut),
      ),
    );
    _badgeSlide = Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _seqController,
        curve: const Interval(0.52, 0.70, curve: Curves.easeOut),
      ),
    );
    _loaderOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _seqController,
        curve: const Interval(0.65, 0.80, curve: Curves.easeOut),
      ),
    );
    _footerOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _seqController,
        curve: const Interval(0.75, 0.90, curve: Curves.easeOut),
      ),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulseScale = Tween(
      begin: 1.0,
      end: 1.35,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));
    _pulseOpacity = Tween(
      begin: 0.4,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeOut));

    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    );

    _startSequence();
  }

  Future<void> _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _seqController.forward();
    await Future.delayed(const Duration(milliseconds: 800));
    _pulseController.repeat();
    _orbController.repeat();
    await Future.delayed(const Duration(milliseconds: 2800));
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, a, __, child) =>
              FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    }
  }

  @override
  void dispose() {
    _seqController.dispose();
    _pulseController.dispose();
    _orbController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _seqController,
          _pulseController,
          _orbController,
        ]),
        builder: (context, _) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(
                    Colors.black,
                    const Color(0xFF0D1B2A),
                    _bgFade.value,
                  )!,
                  Color.lerp(
                    Colors.black,
                    const Color(0xFF132E2A),
                    _bgFade.value,
                  )!,
                  Color.lerp(
                    Colors.black,
                    const Color(0xFF1A4A3A),
                    _bgFade.value,
                  )!,
                ],
              ),
            ),
            child: Stack(
              children: [
                _buildOrbs(),
                Center(
                  child: Column(
                    children: [
                      const Spacer(flex: 3),
                      _buildLogo(),
                      const SizedBox(height: 36),
                      _buildTitle(),
                      const SizedBox(height: 12),
                      _buildSubtitle(),
                      const SizedBox(height: 24),
                      _buildBadge(),
                      const Spacer(flex: 2),
                      _buildLoader(),
                      const Spacer(flex: 1),
                      _buildFooter(),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrbs() {
    final t = _orbController.value;
    return Stack(
      children: [
        _orb(
          x: 0.15,
          y: 0.18 + sin(t * 2 * pi) * 0.02,
          radius: 90,
          color: MedTrackColors.teal.withValues(alpha: 0.07 * _bgFade.value),
        ),
        _orb(
          x: 0.82,
          y: 0.30 + cos(t * 2 * pi) * 0.025,
          radius: 120,
          color: MedTrackColors.secondary.withValues(
            alpha: 0.06 * _bgFade.value,
          ),
        ),
        _orb(
          x: 0.65,
          y: 0.75 + sin(t * 2 * pi + 1.5) * 0.02,
          radius: 70,
          color: MedTrackColors.indigo.withValues(alpha: 0.06 * _bgFade.value),
        ),
        _orb(
          x: 0.20,
          y: 0.80 + cos(t * 2 * pi + 0.8) * 0.015,
          radius: 100,
          color: MedTrackColors.primary.withValues(alpha: 0.05 * _bgFade.value),
        ),
      ],
    );
  }

  Widget _orb({
    required double x,
    required double y,
    required double radius,
    required Color color,
  }) {
    return Positioned(
      left: MediaQuery.of(context).size.width * x - radius / 2,
      top: MediaQuery.of(context).size.height * y - radius / 2,
      child: Container(
        width: radius,
        height: radius,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Pulse ring
          Opacity(
            opacity: _pulseOpacity.value,
            child: Transform.scale(
              scale: _pulseScale.value,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: MedTrackColors.secondary.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          // Static outer ring
          Opacity(
            opacity: _ringOpacity.value,
            child: Transform.scale(
              scale: _ringScale.value,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          // Logo box
          Opacity(
            opacity: _logoOpacity.value,
            child: Transform.scale(
              scale: _logoScale.value,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, Color(0xFFF0F4F2)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: MedTrackColors.teal.withValues(alpha: 0.25),
                      blurRadius: 40,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.local_pharmacy_rounded,
                      size: 50,
                      color: MedTrackColors.primaryDark.withValues(alpha: 0.85),
                    ),
                    Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: MedTrackColors.secondary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: MedTrackColors.secondary.withValues(
                                  alpha: 0.4,
                                ),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    return Opacity(
      opacity: _titleOpacity.value,
      child: SlideTransition(
        position: _titleSlide,
        child: Column(
          children: [
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.1,
                ),
                children: [
                  TextSpan(
                    text: 'Med',
                    style: TextStyle(color: Colors.white),
                  ),
                  TextSpan(
                    text: 'Track',
                    style: TextStyle(color: Color(0xFF5BBFA0)),
                  ),
                  TextSpan(
                    text: '360',
                    style: TextStyle(
                      color: MedTrackColors.secondary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 50,
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(
                  colors: [Color(0xFF5BBFA0), MedTrackColors.secondary],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubtitle() {
    return Opacity(
      opacity: _subtitleOpacity.value,
      child: const Text(
        'Your complete medication\ntracking companion',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          color: Colors.white54,
          letterSpacing: 0.2,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildBadge() {
    return Opacity(
      opacity: _badgeOpacity.value,
      child: SlideTransition(
        position: _badgeSlide,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: MedTrackColors.secondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Ministry of Public Health – Lebanon',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoader() {
    return Opacity(
      opacity: _loaderOpacity.value,
      child: Column(
        children: [
          SizedBox(
            width: 140,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                color: const Color(0xFF5BBFA0),
                minHeight: 3,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Loading your health data...',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Opacity(
      opacity: _footerOpacity.value,
      child: Column(
        children: [
          Text(
            'MEDTRACK360',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.15),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'v1.0.0',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.08),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
