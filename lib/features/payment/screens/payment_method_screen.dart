import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../menu/providers/menu_provider.dart';
import '../../orders/models/order.dart';
import '../../orders/providers/orders_provider.dart';
import '../models/payment_choice.dart';
import '../providers/discount_provider.dart';

/// How the customer wants to pay.
///
/// Nothing is written to the database from this screen. It pops the choice back
/// to checkout, and that is where the order is actually placed — so a customer
/// who opens this page and walks away has created nothing at all.
class PaymentMethodScreen extends ConsumerWidget {
  const PaymentMethodScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final checkout = ref.watch(checkoutProvider);

    // Resolved the same way checkout resolves it, so the figure shown here is
    // the figure the customer just confirmed and not a second, looser estimate.
    // The database remains the authority: payfast-token re-reads orders.total.
    final branchId = checkout.branch?.id;
    final feeAsync = branchId == null
        ? const AsyncValue<double?>.data(null)
        : ref.watch(branchDeliveryFeeProvider(branchId));
    final totals = OrderTotals(
      subtotal: cart.subtotal,
      orderType: checkout.orderType,
      branchDeliveryFee: feeAsync.valueOrNull ?? 0,
    );

    final selection = ref.watch(discountSelectionProvider);
    final discount = resolvedDiscountSummary(
      selection: selection,
      firstOrderOffer: ref.watch(firstOrderOfferProvider((
        subtotal: cart.subtotal,
        branchId: branchId,
      ))).valueOrNull,
      loyalty: ref.watch(discountLoyaltyBalanceProvider),
    );
    final due = (totals.total - (discount?.saving ?? 0))
        .clamp(0.0, double.infinity);

    return Scaffold(
      appBar: AppBar(title: const Text('Payment Method')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _TotalCard(
              due: due,
              itemCount: cart.items.length,
              saving: discount?.saving ?? 0,
            ),
            const SizedBox(height: 24),
            _ChoiceTile(
              icon: Icons.credit_card_rounded,
              title: PaymentChoice.online.label,
              subtitle:
                  'Card, JazzCash, EasyPaisa or bank transfer. Pay securely on '
                  "PayFast's page.",
              badge: 'Recommended',
              onTap: () => context.pop(PaymentChoice.online),
            ),
            const SizedBox(height: 14),
            _ChoiceTile(
              icon: Icons.payments_outlined,
              title: PaymentChoice.cashOnDelivery.label,
              subtitle: 'Pay the rider in cash when your order arrives.',
              onTap: () => context.pop(PaymentChoice.cashOnDelivery),
            ),
            const SizedBox(height: 24),
            Text(
              'Your order is only created once you choose how to pay. '
              'Card details are entered on PayFast\'s own page — MrPizza never '
              'sees or stores them.',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textPrimary.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.due,
    required this.itemCount,
    required this.saving,
  });

  final double due;
  final int itemCount;
  final double saving;

  @override
  Widget build(BuildContext context) {
    return Container(      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount to pay',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Rs. ${due.toStringAsFixed(2)}',
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            saving > 0
                ? '$itemCount item${itemCount == 1 ? '' : 's'} · you saved '
                    'Rs. ${saving.toStringAsFixed(2)}'
                : '$itemCount item${itemCount == 1 ? '' : 's'}',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 12.5,
              color: AppColors.textPrimary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.textPrimary.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textPrimary.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}
