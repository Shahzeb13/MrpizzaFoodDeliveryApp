import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/shared_components.dart';

/// Interactive welcome and role select screen for Mr. Pizza.
class RoleSelectScreen extends ConsumerWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Logo section
              const Center(
                child: MrPizzaLogoWidget(size: 90, showSlogan: true),
              ),
              const SizedBox(height: 30),

              // Hero Banner Image
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.shadowSoft,
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/images/banner_deal.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: AppColors.surfaceDark,
                              child: const Center(
                                child: Text('🍕',
                                    style: TextStyle(fontSize: 80)),
                              ),
                            );
                          },
                        ),
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                AppColors.bannerScrim,
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 24,
                          left: 20,
                          right: 20,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'SPECIAL OFFER',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontFamily,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                    color: Color(0xFF7A5414),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Authentic Wood-Fired\nItalian Pizza Delivered Hot!',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontFamily,
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Enjoy a fresh, wood-fired pizza at your doorstep. No promo needed.',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontFamily,
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Action CTA Button
              SizedBox(
                width: double.infinity,
                height: 58,
                child: FilledButton(
                  onPressed: () {
                    context.go('/home');
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 6,
                    shadowColor: AppColors.primary.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Enter App & Order Now',
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(width: 10),
                      Icon(Icons.arrow_forward_rounded, size: 19),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}