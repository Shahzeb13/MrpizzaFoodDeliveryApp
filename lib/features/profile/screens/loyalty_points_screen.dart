import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';
import '../../orders/providers/loyalty_points_provider.dart';

class LoyaltyPointsScreen extends StatefulWidget {
  const LoyaltyPointsScreen({super.key});

  @override
  State<LoyaltyPointsScreen> createState() => _LoyaltyPointsScreenState();
}

class _LoyaltyPointsScreenState extends State<LoyaltyPointsScreen> {
  int _localPoints = 120;

  final List<Map<String, dynamic>> rewards = const [
    {
      'title': 'Free 500ml Cold Drink',
      'points': 100,
      'icon': Icons.local_drink_rounded,
      'color': AppColors.accent,
    },
    {
      'title': 'Free Garlic Bread Sticks',
      'points': 250,
      'icon': Icons.bakery_dining_rounded,
      'color': AppColors.warning,
    },
    {
      'title': 'Rs. 300 Off Voucher',
      'points': 500,
      'icon': Icons.confirmation_number_rounded,
      'color': AppColors.primary,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final hasScope =
        context.getElementForInheritedWidgetOfExactType<UncontrolledProviderScope>() !=
            null;

    if (hasScope) {
      return Consumer(
        builder: (context, ref, _) {
          final points = ref.watch(loyaltyPointsProvider);
          return _buildContent(context, points, (toDeduct) {
            ref.read(loyaltyPointsProvider.notifier).deductPoints(toDeduct);
          });
        },
      );
    }

    return _buildContent(context, _localPoints, (toDeduct) {
      setState(() {
        _localPoints -= toDeduct;
      });
    });
  }

  Widget _buildContent(
    BuildContext context,
    int points,
    void Function(int) onDeduct,
  ) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Loyalty Points'),
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Points Header Card
            MrDoubleBezel(
              radius: 26,
              innerColor: AppColors.surfaceDark,
              child: Column(
                children: [
                  const MrIconWell(
                    icon: Icons.stars_rounded,
                    color: AppColors.accent,
                    background: Color(0x22E3A63B),
                    size: 30,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$points',
                    style: Theme.of(context).textTheme.displayMedium
                        ?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Available Pizza Points',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.textLight),
                  ),
                  const SizedBox(height: 14),
                  const MrEyebrow(
                    text: 'Earn 1 point on every Rs. 10',
                    background: Color(0x2EFFFFFF),
                    foreground: AppColors.accent,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            const MrSectionTitle(
              title: 'Redeem Rewards',
              eyebrow: 'Perks',
            ),
            const SizedBox(height: 14),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rewards.length,
              itemBuilder: (context, index) {
                final item = rewards[index];
                final canRedeem = points >= (item['points'] as int);
                final color = item['color'] as Color;

                return MrCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  borderRadius: BorderRadius.circular(18),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                            item['icon'] as IconData, color: color, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title'] as String,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item['points']} Points Required',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Compact pill: the app-wide CTA style is a 52dp pill with
                      // 15dp of vertical padding, so the 40dp box starved the
                      // label (10dp for a 21dp line) and Flutter clipped it.
                      // Height and padding have to be overridden together.
                      ElevatedButton(
                        onPressed: canRedeem
                            ? () {
                                onDeduct(item['points'] as int);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Redeemed ${item['title']}!'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 18),
                          disabledBackgroundColor: AppColors.sand,
                          disabledForegroundColor: AppColors.textSecondary,
                        ),
                        child: Text(canRedeem ? 'Redeem' : 'Locked'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}