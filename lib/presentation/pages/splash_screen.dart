import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated splash screen with logo, glow, orbiting particles, and app name.
class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _glowController;
  late final AnimationController _particleController;
  late final AnimationController _textController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _glowSize;
  late final Animation<double> _glowOpacity;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();

    // Logo: scale + fade in
    _logoController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600),
    );
    _logoScale = Tween(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _logoFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOut),
    );

    // Glow pulse behind logo
    _glowController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200),
    );
    _glowSize = Tween(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _glowOpacity = Tween(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Orbiting particles
    _particleController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000),
    );

    // App name text: fade + slide up
    _textController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500),
    );
    _textFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOut),
    );
    _textSlide = Tween(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Start glow + particles immediately
    _glowController.forward();
    _particleController.forward();

    // Small delay then logo enters
    await Future.delayed(const Duration(milliseconds: 150));
    await _logoController.forward();

    // Text slides in after logo
    await Future.delayed(const Duration(milliseconds: 200));
    await _textController.forward();

    // Hold for a moment
    await Future.delayed(const Duration(milliseconds: 700));
    widget.onComplete();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _glowController.dispose();
    _particleController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _logoController, _glowController, _particleController, _textController,
      ]),
      builder: (context, _) {
        return Container(
          color: const Color(0xFF0F1120),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo + glow + particles stack
                SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Glow effect
                      Transform.scale(
                        scale: _glowSize.value,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6C63FF)
                                    .withValues(alpha: _glowOpacity.value),
                                blurRadius: 60,
                                spreadRadius: 20,
                              ),
                              BoxShadow(
                                color: const Color(0xFF00D2FF)
                                    .withValues(alpha: _glowOpacity.value * 0.5),
                                blurRadius: 80,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Orbiting particles
                      ..._buildParticles(),

                      // Logo
                      Opacity(
                        opacity: _logoFade.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Image.asset(
                              'assets/icons/logo.png',
                              width: 110,
                              height: 110,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // App name with gradient shimmer
                SlideTransition(
                  position: _textSlide,
                  child: Opacity(
                    opacity: _textFade.value,
                    child: ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [
                          const Color(0xFF6C63FF),
                          const Color(0xFF00D2FF),
                          const Color(0xFF6C63FF),
                        ],
                        stops: [
                          (_particleController.value - 0.3).clamp(0.0, 1.0),
                          _particleController.value.clamp(0.0, 1.0),
                          (_particleController.value + 0.3).clamp(0.0, 1.0),
                        ],
                      ).createShader(bounds),
                      child: Text(
                        'NoteX',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 6,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildParticles() {
    final progress = _particleController.value;
    final logoFade = _logoFade.value;
    const count = 6;

    return List.generate(count, (i) {
      final angle = (i / count) * 2 * math.pi + progress * 2 * math.pi;
      final radius = 70.0 + math.sin(progress * math.pi) * 15;
      final size = 4.0 + math.sin(angle) * 2;
      final opacity = logoFade * (0.4 + math.sin(angle + progress * math.pi) * 0.3);

      return Positioned(
        left: 100 + math.cos(angle) * radius - size / 2,
        top: 100 + math.sin(angle) * radius - size / 2,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(
              const Color(0xFF6C63FF),
              const Color(0xFF00D2FF),
              (i / count),
            )?.withValues(alpha: opacity),
          ),
        ),
      );
    });
  }
}
