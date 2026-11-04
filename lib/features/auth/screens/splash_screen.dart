import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/neumorphic.dart';

/// Premium Neumorphic Splash and Initial Loading Screen matching Mr. Pizza design style.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  late final Animation<double> _scaleAnimation = Tween<double>(
    begin: 0.96,
    end: 1.04,
  ).animate(CurvedAnimation(
    parent: _animController,
    curve: Curves.easeInOutCubic,
  ));

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeuColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Circular Neumorphic Raised Well with Logo
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NeuColors.background,
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.white,
                      offset: Offset(-8, -8),
                      blurRadius: 18,
                    ),
                    BoxShadow(
                      color: Color(0x33A6B4C9),
                      offset: Offset(8, 8),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFE8EEF6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          offset: const Offset(3, 3),
                          blurRadius: 6,
                        ),
                        const BoxShadow(
                          color: Colors.white,
                          offset: Offset(-3, -3),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 64,
                        height: 64,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Text(
                          '🍕',
                          style: TextStyle(fontSize: 42),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Stylized Title
            const Text(
              'Mr. Pizza',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: NeuColors.textPrimary,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Fresh Italian Pizzas & More',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: NeuColors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 36),

            // Debossed progress indicator
            NeuInset(
              borderRadius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              width: 120,
              height: 10,
              child: const _NeumorphicProgressSweep(),
            ),
          ],
        ),
      ),
    );
  }
}

class _NeumorphicProgressSweep extends StatefulWidget {
  const _NeumorphicProgressSweep();

  @override
  State<_NeumorphicProgressSweep> createState() => _NeumorphicProgressSweepState();
}

class _NeumorphicProgressSweepState extends State<_NeumorphicProgressSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Align(
          alignment: Alignment(-1 + _controller.value * 2, 0),
          child: FractionallySizedBox(
            widthFactor: 0.35,
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: NeuColors.primary,
                borderRadius: BorderRadius.circular(999),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66E51926),
                    blurRadius: 6,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
