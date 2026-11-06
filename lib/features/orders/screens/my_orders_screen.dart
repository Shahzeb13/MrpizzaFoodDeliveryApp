import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/neumorphic.dart';
import '../models/order_tracking.dart';
import '../presentation/order_status_copy.dart';
import '../providers/order_tracking_provider.dart';

/// The customer's real order history matching the Neumorphic aesthetic.
class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(myOrdersProvider);

    return Scaffold(
      backgroundColor: NeuColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'My Orders',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: NeuColors.textPrimary,
            letterSpacing: -0.4,
          ),
        ),
        leading: Center(
          child: NeuCircleButton(
            size: 40,
            onPressed: () => Navigator.of(context).canPop()
                ? Navigator.of(context).pop()
                : context.go('/home'),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: NeuColors.textPrimary,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          ordersAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: NeuColors.primary),
            ),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NeuInset(
                      borderRadius: 30,
                      padding: const EdgeInsets.all(16),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        size: 36,
                        color: NeuColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'We could not load your orders.',
                      style: TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: NeuColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: NeuColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
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
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NeuInset(
                          borderRadius: 36,
                          padding: const EdgeInsets.all(22),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            size: 44,
                            color: NeuColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'No orders yet',
                          style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: NeuColors.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'When you place an order it will appear here, with its real bill number and live status.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 13,
                            color: NeuColors.textSecondary,
                            height: 1.4,
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
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: orders.length,
                  itemBuilder: (context, index) =>
                      _buildOrderCard(context, ref, orders[index]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(
    BuildContext context,
    WidgetRef ref,
    OrderSummary order,
  ) {
    final isDone = order.stage == OrderStage.delivered;
    final isCancelled = order.stage == OrderStage.cancelled;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: NeuCard(
        padding: const EdgeInsets.all(18),
        borderRadius: 24,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    order.billNumber ?? 'Order',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: NeuColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDone
                        ? const Color(0xFFE8F5E9)
                        : isCancelled
                            ? const Color(0xFFFFEBEE)
                            : NeuColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusLabel(order.status).toUpperCase(),
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: isDone
                          ? const Color(0xFF2E7D32)
                          : isCancelled
                              ? const Color(0xFFC62828)
                              : Colors.white,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              order.createdAt == null
                  ? ''
                  : '${formatDayLabel(order.createdAt!)} · ${formatClockTime(order.createdAt!)}',
              style: const TextStyle(
                fontFamily: 'PlusJakartaSans',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: NeuColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            NeuInset(
              borderRadius: 14,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_pizza_outlined,
                    size: 16,
                    color: NeuColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.itemSummary?.isNotEmpty ?? false
                          ? order.itemSummary!
                          : '${order.itemCount} item(s)',
                      style: const TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: NeuColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total amount',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: NeuColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Rs. ${order.total.toInt()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: NeuColors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    ref.read(trackedOrderIdProvider.notifier).state =
                        order.orderId;
                    context.push('/orders/track');
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: NeuColors.primary,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x4DE51926),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      order.isStillMoving ? 'Track Order' : 'View Order',
                      style: const TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Every receipt offers the way out if this specific order went
            // wrong; the support email it composes names the order.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    context.push('/support', extra: order.billNumber),
                icon: const Icon(
                  Icons.support_agent_rounded,
                  size: 16,
                  color: NeuColors.primary,
                ),
                label: const Text(
                  'Problem with this order?',
                  style: TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: NeuColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
