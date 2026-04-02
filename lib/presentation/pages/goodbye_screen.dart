import 'package:flutter/material.dart';

/// Animated goodbye screen: logo fades in, pulses with an expanding
/// ring of light, then shrinks to a dot and disappears.
class GoodbyeScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const GoodbyeScreen({super.key, required this.onComplete});

  @override
  State<GoodbyeScreen> createState() => _GoodbyeScreenState();
}

class _GoodbyeScreenState extends State<GoodbyeScreen>
    with TickerProviderStateMixin {
  // Phase 1: logo + text fade in
  late final AnimationController _enterController;
  late final Animation<double> _enterFade;
  late final Animation<double> _enterScale;

  // Phase 2: pulse glow + expanding ring
  late final AnimationController _pulseController;
  late final Animation<double> _pulseGlow;
  late final Animation<double> _ringScale;
  late final Animation<double> _ringFade;

  // Phase 3: shrink to dot + fade out
  late final AnimationController _shrinkController;
  late final Animation<double> _shrinkScale;
  late final Animation<double> _shrinkFade;

  @override
  void initState() {
    super.initState();

    // Phase 1: enter
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _enterFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _enterController, curve: Curves.easeOut),
    );
    _enterScale = Tween(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _enterController, curve: Curves.easeOutBack),
    );

    // Phase 2: pulse + ring
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseGlow = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.3), weight: 60),
    ]).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
    _ringScale = Tween(begin: 0.5, end: 4.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOutCubic),
    );
    _ringFade = Tween(begin: 0.6, end: 0.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    // Phase 3: shrink away
    _shrinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shrinkScale = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _shrinkController, curve: Curves.easeInBack),
    );
    _shrinkFade = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _shrinkController, curve: Curves.easeIn),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    // Enter
    await _enterController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    // Pulse + ring
    await _pulseController.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    // Shrink away
    await _shrinkController.forward();
    await Future.delayed(const Duration(milliseconds: 100));
    widget.onComplete();
  }

  @override
  void dispose() {
    _enterController.dispose();
    _pulseController.dispose();
    _shrinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _enterController, _pulseController, _shrinkController,
      ]),
      builder: (context, _) {
        // Combine enter fade with shrink fade
        final opacity = _enterFade.value * _shrinkFade.value;
        final scale = _enterScale.value * _shrinkScale.value;

        return Container(
          color: const Color(0xFF0F1120),
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Expanding ring
                if (_pulseController.value > 0)
                  Transform.scale(
                    scale: _ringScale.value,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF6C63FF)
                              .withValues(alpha: _ringFade.value),
                          width: 2,
                        ),
                      ),
                    ),
                  ),

                // Second ring (slightly delayed feel via different opacity)
                if (_pulseController.value > 0.1)
                  Transform.scale(
                    scale: _ringScale.value * 0.7,
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF00D2FF)
                              .withValues(alpha: _ringFade.value * 0.5),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),

                // Pulse glow behind logo
                if (_pulseController.value > 0)
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6C63FF)
                              .withValues(alpha: _pulseGlow.value * 0.4),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                        BoxShadow(
                          color: const Color(0xFF00D2FF)
                              .withValues(alpha: _pulseGlow.value * 0.25),
                          blurRadius: 60,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                  ),

                // Logo + text
                Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: scale.clamp(0.0, 2.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Image.asset(
                            'assets/icons/logo.png',
                            width: 80,
                            height: 80,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'See you soon',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                                letterSpacing: 2,
                                decoration: TextDecoration.none,
                              ),
                        ),
                      ],
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
}
