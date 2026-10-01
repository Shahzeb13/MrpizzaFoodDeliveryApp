import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../orders/models/order_tracking.dart';
import '../orders/presentation/order_status_copy.dart';
import '../orders/providers/live_order_provider.dart';
import '../orders/providers/order_tracking_provider.dart';

/// How long an order can sit unfinished before this stops counting as "one in
/// progress".
///
/// Without a bound, a warning would nag forever — which is the same trap as
/// blocking, only milder. A branch that forgets to close an order would leave
/// that customer being asked about it on every single checkout, with no way to
/// make it stop. Anything older than this is broken data, not a real delivery,
/// and gets out of the way.
///
/// Generous on purpose: three hours comfortably covers a slow delivery, a
/// backlog at the branch, and a rider held up in traffic.
const Duration orderInProgressWarningWindow = Duration(hours: 3);

/// The customer's own unfinished order, if it is recent enough to be real.
OrderSummary? findOrderInProgress(
  List<OrderSummary> orders,
  DateTime now, {
  Duration window = orderInProgressWarningWindow,
}) {
  // Sorted here rather than trusting the caller's ordering. `my_orders` happens
  // to return newest-first today, so the first match would usually be right —
  // but "newest unfinished order" is a rule the warning depends on, and rules
  // that depend on someone else's ORDER BY are one schema change away from
  // quietly reporting the wrong order.
  final newestFirst = [...orders]
    ..sort((a, b) {
      final aAt = a.createdAt;
      final bAt = b.createdAt;
      if (aAt == null) return 1;
      if (bAt == null) return -1;
      return bAt.compareTo(aAt);
    });

  for (final order in newestFirst) {
    if (!order.isStillMoving) continue;
    final createdAt = order.createdAt;
    // No timestamp cannot be age-checked, and treating it as live is how a
    // broken row nags forever. Skipping is the safe direction.
    if (createdAt == null) continue;
    if (now.difference(createdAt) > window) continue;
    return order;
  }
  return null;
}

/// Opens checkout, or explains that an order is already on its way.
///
/// Deliberately a warning and not a block. Hard-blocking is what the big apps
/// do, and for them it is a support cost they can absorb. Here it would be
/// dangerous: this project's own database has held orders open in `confirmed`
/// indefinitely, and a block keyed on "anything not delivered or cancelled"
/// would leave those customers permanently unable to order anything again, with
/// no recourse. A warning costs one extra tap for the rare customer who really
/// does want two orders, and cannot lock anyone out.
Future<void> startCheckoutGuarded(BuildContext context, WidgetRef ref) async {
  final orders = ref.read(myOrdersProvider).value ?? const <OrderSummary>[];
  final inProgress = findOrderInProgress(orders, DateTime.now());

  if (inProgress == null) {
    context.push('/checkout');
    return;
  }

  final proceedAnyway = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _OrderInProgressDialog(order: inProgress),
  );

  if (proceedAnyway != true || !context.mounted) return;

  // Ordering again is a decision, so the bar follows the NEW order from here.
  // Without this the bar stays pinned to the old one and the customer is told
  // their second order is confirmed while watching the first.
  ref.read(pinnedLiveOrderIdProvider.notifier).state = null;
  context.push('/checkout');
}

class _OrderInProgressDialog extends StatelessWidget {
  const _OrderInProgressDialog({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = stageColorFor(order.stage);
    final bill = order.billNumber?.isNotEmpty ?? false
        ? '#${order.billNumber}'
        : 'Your order';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.primaryTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(height: 12),
            Text('You already have an order on the way',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    statusLabel(order.status),
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    bill,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text(
                  'Track that order',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                // The escape hatch, and it must be a real one. A customer who
                // genuinely needs a second order must not be trapped by a
                // warning.
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  'Order anyway',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
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