import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/widgets.dart';
import '../models/order_tracking.dart';
import '../presentation/order_status_copy.dart';
import '../providers/order_tracking_provider.dart';

/// The customer's real order history.
///
/// This list used to be three hardcoded `Map<String, dynamic>` rows — invented
/// bill numbers, invented dates like "08 Sep 2026", invented totals — merged
/// with whatever the in-memory demo order list happened to hold. Every row here
/// is now an `orders` row for the signed-in customer, read through `my_orders()`.
class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(myOrdersProvider);

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
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.receipt_long_rounded,
                    size: 44, color: AppColors.textLight),
                const SizedBox(height: 14),
                const Text(
                  'We could not load your orders.',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => ref.invalidate(myOrdersProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_rounded,
                        size: 44, color: AppColors.textLight),
                    SizedBox(height: 14),
                    Text(
                      'No orders yet',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'When you place an order it will appear here, with its real '
                      'bill number and total.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myOrdersProvider);
              await ref.read(myOrdersProvider.future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              itemBuilder: (context, index) =>
                  _buildOrderCard(context, ref, orders[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(
    BuildContext context,
    WidgetRef ref,
    OrderSummary order,
  ) {
    final stageColor = stageColorFor(order.stage);

    return MrCard(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  order.billNumber ?? 'Order',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: 12),
              // Flexible on both sides, and an ellipsis on the status itself.
              // "Preparing in the kitchen" is roughly twice the width of
              // "Cancelled", so a card that fitted the short labels overflowed
              // the row by well over a hundred pixels on the long ones — the
              // badge was the thing deciding whether the card fit on screen,
              // which is exactly backwards now that the status updates live.
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: stageColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: stageColor.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: stageColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          statusLabel(order.status),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: stageColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // The date has to be allowed to give way. It is the only elastic
              // thing on this line and the eyebrow is the part worth keeping
              // whole, so the date is the one that ellipsises.
              Flexible(
                child: Text(
                  order.createdAt == null
                      ? ''
                      : '${formatDayLabel(order.createdAt!)}  ${formatClockTime(order.createdAt!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 10),
              if (order.isStillMoving)
                const MrEyebrow(
                  text: 'In progress',
                  background: AppColors.primaryTint,
                  foreground: AppColors.primaryDark,
                ),
            ],
          ),
          const SizedBox(height: 12),
          const MrFadeDivider(),
          const SizedBox(height: 12),
          Text(
            order.itemSummary?.isNotEmpty ?? false
                ? order.itemSummary!
                : '${order.itemCount} item(s)',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textPrimary, height: 1.35),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Expanded rather than spaceBetween: the total is the variable
              // width here — a four-figure order total with thousands separators
              // is not the same width as a small one — and it was the row that
              // pushed "Track Order" off the edge of a narrow phone.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Total',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 2),
                    MrPriceText(order.total, fontSize: 17),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  // The tracking screen follows a real order id, not an
                  // in-memory list entry.
                  ref.read(trackedOrderIdProvider.notifier).state =
                      order.orderId;
                  context.push('/orders/track');
                },
                child: Text(order.isStillMoving ? 'Track Order' : 'View Order'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
