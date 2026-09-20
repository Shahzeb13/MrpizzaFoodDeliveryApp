import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/widgets.dart';

class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  int currentStep = 2;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Live Order Tracking'),
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order ID & Status Header Card
            MrDoubleBezel(
              radius: 28,
              innerColor: AppColors.surfaceDark,
              outerPadding: const EdgeInsets.all(6),
              innerPadding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ORDER #MP-9842',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              fontFamily: AppTheme.fontFamily,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Baking & On The Way!',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Estimated arrival in 14 minutes',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.textLight),
                          ),
                        ],
                      ),
                      const MrDoubleBezel(
                        radius: 20,
                        outerPadding: EdgeInsets.all(4),
                        innerPadding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        innerColor: AppColors.surfaceDark,
                        trayColor: AppColors.primary,
                        child: Column(
                          children: [
                            Text(
                              'EST. TIME',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                                fontFamily: AppTheme.fontFamily,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '14 MIN',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                fontFamily: AppTheme.fontFamily,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Live Simulation Map Box
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.shadowSoft,
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Map Background Styling
                  ClipRRect(
                    borderRadius: BorderRadius.circular(23),
                    child: Container(
                      color: AppColors.sand,
                      child: Stack(
                        children: [
                          // Road Grid Lines
                          Positioned(
                            top: 40,
                            left: 0,
                            right: 0,
                            child: Container(
                                height: 16, color: AppColors.surface),
                          ),
                          Positioned(
                            top: 110,
                            left: 0,
                            right: 0,
                            child: Container(
                                height: 24, color: AppColors.surface),
                          ),
                          Positioned(
                            left: 100,
                            top: 0,
                            bottom: 0,
                            child: Container(
                                width: 18, color: AppColors.surface),
                          ),
                          Positioned(
                            right: 90,
                            top: 0,
                            bottom: 0,
                            child: Container(
                                width: 22, color: AppColors.surface),
                          ),
                          Positioned(
                            left: 70,
                            top: 70,
                            child: Container(
                              width: 10,
                              height: 80,
                              transform: Matrix4.rotationZ(-0.4),
                              color: AppColors.surface,
                            ),
                          ),
                          // Delivery Destination Pin
                          Positioned(
                            right: 60,
                            top: 30,
                            child: Column(
                              children: [
                                const Icon(Icons.location_on,
                                    color: AppColors.primary, size: 36),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: AppColors.borderDeep),
                                  ),
                                  child: const Text(
                                    'Home',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                      fontFamily: AppTheme.fontFamily,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Rider Pin
                          Positioned(
                            left: 90,
                            top: 95,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: AppColors.surface, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.two_wheeler,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                        boxShadow: const [
                          BoxShadow(
                              color: AppColors.shadowSoft, blurRadius: 8),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.near_me,
                              color: AppColors.primary, size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Rider Marco is 1.2 km away from your location',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                                fontFamily: AppTheme.fontFamily,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Rider Contact Info Card
            MrCard(
              padding: const EdgeInsets.all(16),
              borderRadius: BorderRadius.circular(20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.borderDeep),
                    ),
                    child: const Icon(Icons.delivery_dining,
                        color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Marco Rossi',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded,
                                size: 13, color: AppColors.accent),
                            const SizedBox(width: 3),
                            Text(
                              '4.95  |  Mr. Pizza Senior Rider',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const MrIconWell(
                      icon: Icons.call_rounded,
                      color: AppColors.success,
                      background: Color(0xFFE4F1E8),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Calling Rider Marco Rossi (+1 555-0192)...')),
                      );
                    },
                  ),
                  IconButton(
                    icon: const MrIconWell(
                      icon: Icons.chat_bubble_rounded,
                      color: AppColors.primary,
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Opening Chat with Marco...')),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            const MrSectionTitle(
              eyebrow: 'Progress',
              title: 'Order Pipeline',
            ),
            const SizedBox(height: 18),

            _buildTrackingStep(
              index: 0,
              title: 'Order Confirmed',
              subtitle: 'Restaurant received your order at 12:45 PM',
              icon: Icons.check_circle,
              isCompleted: true,
            ),
            _buildTrackingStep(
              index: 1,
              title: 'Baking in Wood-Fired Oven',
              subtitle: 'Chef is baking your pizza with fresh ingredients',
              icon: Icons.local_fire_department,
              isCompleted: true,
            ),
            _buildTrackingStep(
              index: 2,
              title: 'Out for Delivery',
              subtitle: 'Marco picked up your pizza and is on his way',
              icon: Icons.delivery_dining,
              isCompleted: true,
              isCurrent: true,
            ),
            _buildTrackingStep(
              index: 3,
              title: 'Delivered Hot & Fresh',
              subtitle: 'Enjoy your Mr. Pizza feast!',
              icon: Icons.home,
              isCompleted: false,
              isLast: true,
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackingStep({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isCompleted,
    bool isCurrent = false,
    bool isLast = false,
  }) {
    final color = isCurrent
        ? AppColors.primary
        : isCompleted
            ? AppColors.success
            : AppColors.textLight;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.13),
                shape: BoxShape.circle,
                border: Border.all(
                    color: color, width: isCurrent ? 2 : 1.4),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 36,
                color: isCompleted
                    ? AppColors.success.withValues(alpha: 0.5)
                    : AppColors.border,
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color:
                        isCurrent ? AppColors.primary : AppColors.textPrimary,
                    fontFamily: AppTheme.fontFamily,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}