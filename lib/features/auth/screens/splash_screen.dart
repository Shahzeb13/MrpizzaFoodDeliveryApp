import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// Branded splash / app-start loading screen.
///
/// Shown by [AuthGate] while the initial Supabase session check runs, so an
/// already-logged-in user is redirected straight to their panel without a flash
/// of the login screen. It holds no navigation logic of its own.
///
/// Deliberately quiet: one mark, one wordmark, one hairline of motion. The app
/// is warm ivory, so the splash sits on the same surface — a dark splash here
/// reads as a broken flash before the first screen appears.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: FadeTransition(
          opacity: _fadeController,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/logo.png',
                width: 76,
                height: 76,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
              const SizedBox(height: 20),
              const Text(
                'Mr. Pizza',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 28),
              const _SlimProgressBar(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 2px hairline that sweeps left to right, used instead of a spinner so the
/// wait reads as a considered transition rather than a blocking dialog.
class _SlimProgressBar extends StatefulWidget {
  const _SlimProgressBar();

  @override
  State<_SlimProgressBar> createState() => _SlimProgressBarState();
}

class _SlimProgressBarState extends State<_SlimProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 2,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              // Sweeps from fully left to fully right, then jumps back to the
              // start — an indeterminate loop with no visible seam.
              return Align(
                alignment: Alignment(-1 + _controller.value * 2, 0),
                child: FractionallySizedBox(
                  widthFactor: 0.4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
