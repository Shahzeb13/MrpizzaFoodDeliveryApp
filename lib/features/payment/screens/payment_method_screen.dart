import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/neumorphic.dart';
import '../../menu/providers/menu_provider.dart';
import '../../orders/models/order.dart';
import '../../orders/providers/orders_provider.dart';
import '../models/payment_choice.dart';
import '../providers/discount_provider.dart';

/// How the customer wants to pay in the exact Neumorphic design language.
class PaymentMethodScreen extends ConsumerWidget {
  const PaymentMethodScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final checkout = ref.watch(checkoutProvider);

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
      backgroundColor: NeuColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Payment Method',
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
            onPressed: () => context.pop(),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: NeuColors.textPrimary,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
              badge: 'RECOMMENDED',
              onTap: () => context.pop(PaymentChoice.online),
            ),
            const SizedBox(height: 16),
            _ChoiceTile(
              icon: Icons.payments_outlined,
              title: PaymentChoice.cashOnDelivery.label,
              subtitle: 'Pay the rider in cash when your order arrives.',
              onTap: () => context.pop(PaymentChoice.cashOnDelivery),
            ),
            const SizedBox(height: 26),
            NeuInset(
              borderRadius: 20,
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.security_rounded,
                    color: NeuColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your order is only created once you choose how to pay. '
                      'Card details are entered on PayFast\'s encrypted page — Mr. Pizza '
                      'never sees or stores them.',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: NeuColors.textSecondary,
                      ),
                    ),
                  ),
                ],
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
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Amount to pay',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF9EA3AE),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: NeuColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$itemCount item${itemCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Rs. ${due.toInt()}',
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              color: Colors.white,
            ),
          ),
          if (saving > 0) ...[
            const SizedBox(height: 8),
            Text(
              'You saved Rs. ${saving.toInt()} on this order',
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4CAF50),
              ),
            ),
          ],
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
    return NeuCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 24,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: NeuColors.primary,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66E51926),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
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
                          fontWeight: FontWeight.w900,
                          color: NeuColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      NeuPillBadge(
                        label: badge!,
                        textColor: NeuColors.primary,
                        isInset: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: NeuColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right_rounded,
            color: NeuColors.textSecondary,
            size: 22,
          ),
        ],
      ),
    );
  }
}
