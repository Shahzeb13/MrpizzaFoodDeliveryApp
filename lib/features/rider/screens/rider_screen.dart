import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/widgets.dart';
import '../../../widgets/shared_components.dart';

class RiderScreen extends ConsumerStatefulWidget {
  const RiderScreen({super.key});

  @override
  ConsumerState<RiderScreen> createState() => _RiderScreenState();
}

enum DeliveryStep {
  newOffer,
  accepted,
  pickedUp,
  delivered,
}

class _RiderScreenState extends ConsumerState<RiderScreen> {
  bool isOnline = true;
  DeliveryStep currentStep = DeliveryStep.accepted;
  double todayEarnings = 2450.0;
  int completedCount = 8;

  final List<Map<String, String>> completedDeliveries = [
    {
      'id': '#MP-84910',
      'customer': 'Usama Khan',
      'address': 'Mandian, Abbottabad',
      'time': '1:45 PM',
      'payout': 'Rs. 250',
    },
    {
      'id': '#MP-73921',
      'customer': 'Hamza Ahmed',
      'address': 'Jinnahabad, Abbottabad',
      'time': '12:30 PM',
      'payout': 'Rs. 220',
    },
    {
      'id': '#MP-62019',
      'customer': 'Saad Malik',
      'address': 'Pine City, Abbottabad',
      'time': '11:15 AM',
      'payout': 'Rs. 300',
    },
  ];

  void _advanceDeliveryStep() {
    setState(() {
      if (currentStep == DeliveryStep.newOffer) {
        currentStep = DeliveryStep.accepted;
        showTopCartToast(context, 'Job Accepted! Proceed to Kitchen.');
      } else if (currentStep == DeliveryStep.accepted) {
        currentStep = DeliveryStep.pickedUp;
        showTopCartToast(
            context, 'Order Picked Up! Head to COMSATS Abbottabad.');
      } else if (currentStep == DeliveryStep.pickedUp) {
        currentStep = DeliveryStep.delivered;
        todayEarnings += 250;
        completedCount += 1;
        completedDeliveries.insert(0, {
          'id': '#MP-98420',
          'customer': 'Aalyan Mughal',
          'address': 'COMSATS Abbottabad, Hostel 3',
          'time': 'Just Now',
          'payout': 'Rs. 250',
        });
        showTopCartToast(context, 'Delivery Completed! Rs. 250 added.');
      } else if (currentStep == DeliveryStep.delivered) {
        currentStep = DeliveryStep.newOffer;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: const Text('Rider Dashboard'),
        actions: [
          // Online Status Badge & Switch
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isOnline
                  ? const Color(0xFFE4F1E8)
                  : AppColors.sand,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isOnline
                    ? AppColors.success.withValues(alpha: 0.4)
                    : AppColors.borderDeep,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color:
                        isOnline ? AppColors.success : AppColors.textLight,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isOnline ? 'ONLINE' : 'OFFLINE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color:
                        isOnline ? AppColors.success : AppColors.textSecondary,
                    fontFamily: AppTheme.fontFamily,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats Cards Row
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      label: 'Today\'s Earnings',
                      value: 'Rs. ${todayEarnings.toStringAsFixed(0)}',
                      icon: Icons.account_balance_wallet_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      label: 'Completed',
                      value: '$completedCount Jobs',
                      icon: Icons.check_circle_rounded,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatCard(
                      label: 'Rating',
                      value: '4.95',
                      icon: Icons.star_rounded,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Active Delivery Task Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const MrSectionTitle(
                    title: 'Current Delivery Task',
                  ),
                  if (isOnline &&
                      currentStep != DeliveryStep.delivered &&
                      currentStep != DeliveryStep.newOffer)
                    const MrEyebrow(
                      text: 'En Route',
                      background: AppColors.primaryTint,
                      foreground: AppColors.primaryDark,
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // Active Task Card Logic
              if (!isOnline)
                _buildOfflineCard()
              else if (currentStep == DeliveryStep.delivered)
                _buildDeliveredSuccessCard()
              else if (currentStep == DeliveryStep.newOffer)
                _buildNewOfferCard()
              else
                _buildActiveOrderCard(),

              const SizedBox(height: 26),

              // Completed Deliveries Log
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const MrSectionTitle(title: 'Recent Deliveries'),
                  Text(
                    'Today',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              ...completedDeliveries.map((item) => _buildHistoryTile(item)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return MrCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MrIconWell(icon: icon, color: color, size: 18),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineCard() {
    return MrCard(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      borderRadius: BorderRadius.circular(20),
      child: Column(
        children: [
          const MrIconWell(
            icon: Icons.power_settings_new_rounded,
            color: AppColors.textSecondary,
            background: AppColors.sand,
            size: 28,
          ),
          const SizedBox(height: 14),
          Text(
            'You are Offline',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Switch duty to ONLINE at the top right to start receiving orders.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveredSuccessCard() {
    return MrDoubleBezel(
      radius: 24,
      innerColor: const Color(0xFFE4F1E8),
      child: Column(
        children: [
          const MrIconWell(
            icon: Icons.check_circle_rounded,
            color: AppColors.success,
            background: Color(0xFFD0E8D8),
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            'Order Delivered Successfully!',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Payout of Rs. 250 has been credited.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() => currentStep = DeliveryStep.newOffer);
              },
              child: const Text('Ready for Next Delivery'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewOfferCard() {
    return MrCard(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const MrEyebrow(
                text: 'New Offer',
                background: AppColors.goldTint,
                foreground: Color(0xFF9A6B1F),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Text(
                  'Payout: Rs. 250',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: AppColors.success),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Order #MP-98420',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Pickup: Supply Bazaar -> Dropoff: COMSATS Abbottabad',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _advanceDeliveryStep,
              child: const Text('Accept Order Offer'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveOrderCard() {
    return MrCard(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order ID & Payout Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order #MP-98420',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Payout: Rs. 250',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: AppColors.success),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Route Timeline (Clean Dots & Lines)
          _buildRouteRow(
            isPickup: true,
            title: 'Pickup: Mr. Pizza Main Kitchen',
            subtitle: 'Supply Bazaar, Abbottabad',
          ),
          Padding(
            padding: const EdgeInsets.only(left: 7),
            child: Container(
              width: 2,
              height: 16,
              color: AppColors.borderDeep,
            ),
          ),
          _buildRouteRow(
            isPickup: false,
            title: 'Dropoff: Aalyan Mughal',
            subtitle: 'COMSATS Abbottabad, Hostel 3, Room 204',
          ),

          const MrFadeDivider(),
          const SizedBox(height: 16),

          // Order Items & Payment
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Items (3)',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Fajita Pizza, Garlic Knots, Pepsi',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Cash to Collect',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Rs. 1,600',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: AppColors.warning),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Call & Maps Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    showTopCartToast(
                        context, 'Calling customer +923316290108...');
                  },
                  icon: const Icon(Icons.phone,
                      size: 16, color: AppColors.primary),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Call Customer'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    showTopCartToast(
                        context, 'Opening Abbottabad Maps Navigation...');
                  },
                  icon: const Icon(Icons.navigation_rounded,
                      size: 16, color: Colors.white),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Navigation'),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Primary State CTA Action Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _advanceDeliveryStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: currentStep == DeliveryStep.accepted
                    ? AppColors.warning
                    : AppColors.success,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  currentStep == DeliveryStep.accepted
                      ? 'Confirm Picked Up from Kitchen'
                      : 'Mark Delivered & Collect Cash',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteRow({
    required bool isPickup,
    required String title,
    required String subtitle,
  }) {
    final color = isPickup ? AppColors.warning : AppColors.success;
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTile(Map<String, String> item) {
    return MrCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderRadius: BorderRadius.circular(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Color(0xFFE4F1E8),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: AppColors.success, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item['id']!,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '• ${item['customer']!}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                Text(
                  item['address']!,
                  style: Theme.of(context).textTheme.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item['payout']!,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: AppColors.success),
              ),
              Text(
                item['time']!,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}