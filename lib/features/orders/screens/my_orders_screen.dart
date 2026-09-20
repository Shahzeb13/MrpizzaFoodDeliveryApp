import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';

class MyOrdersScreen extends StatelessWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> orders = [
      {
        'id': '#MP-84920',
        'date': 'Today, 2:15 PM',
        'items': '1x Chicken Tikka Supreme (Large), 1x Garlic Bread',
        'total': 1850,
        'status': 'Preparing',
        'statusColor': AppColors.warning,
        'isActive': true,
      },
      {
        'id': '#MP-72104',
        'date': '08 Sep 2026',
        'items': '2x Zinger Burger Deal, 1x 1.5L Pepsi',
        'total': 1490,
        'status': 'Delivered',
        'statusColor': AppColors.success,
        'isActive': false,
      },
      {
        'id': '#MP-61029',
        'date': '24 Aug 2026',
        'items': '1x Pepperoni Feast (Medium)',
        'total': 990,
        'status': 'Delivered',
        'statusColor': AppColors.success,
        'isActive': false,
      },
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Orders'),
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          final isActive = order['isActive'] as bool;
          return MrCard(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      order['id'] as String,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: (order['statusColor'] as Color)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: (order['statusColor'] as Color)
                              .withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: order['statusColor'] as Color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            order['status'] as String,
                            style: TextStyle(
                              color: order['statusColor'] as Color,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      order['date'] as String,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (isActive)
                      const MrEyebrow(
                        text: 'Active',
                        background: AppColors.primaryTint,
                        foreground: AppColors.primaryDark,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const MrFadeDivider(),
                const SizedBox(height: 12),
                Text(
                  order['items'] as String,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.textPrimary, height: 1.35),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 2),
                        MrPriceText(
                          (order['total'] as num),
                          fontSize: 17,
                        ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed: () {
                        context.push('/orders/track');
                      },
                      child: Text(
                        isActive ? 'Track Order' : 'Reorder',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}