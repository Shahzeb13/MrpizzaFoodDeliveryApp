import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';

class MyOrdersScreen extends StatelessWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> orders = [
      {
        'id': '#MP-84920',
        'date': 'Today, 2:15 PM',
        'items': '1x Chicken Tikka Supreme (Large), 1x Garlic Bread',
        'total': 'Rs. 1,850',
        'status': 'Preparing 👨‍🍳',
        'statusColor': Colors.orange,
        'isActive': true,
      },
      {
        'id': '#MP-72104',
        'date': '08 Sep 2026',
        'items': '2x Zinger Burger Deal, 1x 1.5L Pepsi',
        'total': 'Rs. 1,490',
        'status': 'Delivered ✅',
        'statusColor': Colors.green,
        'isActive': false,
      },
      {
        'id': '#MP-61029',
        'date': '24 Aug 2026',
        'items': '1x Pepperoni Feast (Medium)',
        'total': 'Rs. 990',
        'status': 'Delivered ✅',
        'statusColor': Colors.green,
        'isActive': false,
      },
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text(
          'My Orders',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, index) {
          final order = orders[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: order['isActive'] as bool ? AppColors.primary : AppColors.border,
                width: order['isActive'] as bool ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      order['id'] as String,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (order['statusColor'] as Color).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        order['status'] as String,
                        style: TextStyle(
                          color: order['statusColor'] as Color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  order['date'] as String,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const Divider(height: 20, color: AppColors.border),
                Text(
                  order['items'] as String,
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.3),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total: ${order['total']}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.primary),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        context.push('/orders/track');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        order['isActive'] as bool ? 'Track Order' : 'Reorder',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
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
