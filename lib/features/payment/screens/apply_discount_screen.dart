import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/widgets.dart';
import '../../loyalty/widgets/spend_points_control.dart';
import '../../menu/providers/menu_provider.dart';
import '../../orders/providers/orders_provider.dart';
import '../data/voucher_repository.dart';
import '../models/discount.dart';
import '../models/voucher.dart';
import '../providers/discount_provider.dart';

/// Where vouchers and loyalty points are chosen.
///
/// This used to be two blocks at the foot of the cart — a code field and a points
/// stepper — which pushed the totals off the bottom of the screen on a small
/// phone and made the two rules about each other invisible. Both now live here,
/// with the one rule that connects them stated out loud: an order carries one
/// saving, so whichever is applied locks the other until it is removed.
///
/// The cart keeps the choice ([discountSelectionProvider]) rather than this
/// screen, so navigating back shows it rather than losing it.
class ApplyDiscountScreen extends ConsumerStatefulWidget {
  const ApplyDiscountScreen({super.key});

  @override
  ConsumerState<ApplyDiscountScreen> createState() =>
      _ApplyDiscountScreenState();
}

class _ApplyDiscountScreenState extends ConsumerState<ApplyDiscountScreen> {
  final _voucherController = TextEditingController();
  bool _isCheckingVoucher = false;

  @override
  void dispose() {
    _voucherController.dispose();
    super.dispose();
  }

  /// Asks the database whether the typed code can be used on this cart, and
  /// keeps it only if the database says yes.
  ///
  /// The code is not judged here. Active, in-date, minimum subtotal,
  /// per-customer limit, total limit and the branch it is restricted to are all
  /// read from the vouchers table by `validate_voucher`, so a code this screen
  /// accepts is a code the database accepted for this exact cart.
  Future<void> _applyTypedCode() async {
    FocusScope.of(context).unfocus();
    final code = _voucherController.text.trim();

    if (code.isEmpty) {
      _showMessage('Please enter a voucher code', isError: true);
      return;
    }
    if (_isCheckingVoucher) return;

    final cart = ref.read(cartProvider);
    setState(() => _isCheckingVoucher = true);

    VoucherCheck verdict;
    try {
      verdict = await ref.read(voucherRepositoryProvider).validateVoucher(
            code: code,
            subtotal: cart.subtotal,
            menuItemIds: cart.items.map((line) => line.item.id).toList(),
            // A free-delivery voucher is waived against the fulfilling branch's
            // fee, so the database needs to know which branch that is.
            branchId: ref.read(checkoutProvider).branch?.id,
          );
    } catch (error) {
      // The customer only ever sees "we could not check that code", which is
      // true of a dropped connection and of a database function that has
      // changed underneath the app. Those are very different problems and the
      // log line is the only thing that tells them apart.
      developer.log(
        'validate_voucher could not be called.',
        name: 'mrpizza.voucher',
        error: error,
      );
      if (!mounted) return;
      setState(() => _isCheckingVoucher = false);
      _showMessage(
        'We could not check that code right now. Please try again.',
        isError: true,
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isCheckingVoucher = false);

    if (!verdict.isUsable) {
      _showMessage(verdict.message, isError: true);
      return;
    }

    ref.read(discountSelectionProvider.notifier).applyVoucher(
          DiscountSelection(voucher: verdict),
        );
    _voucherController.clear();
    _showMessage(verdict.message);
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(discountSelectionProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text(
          'Voucher & Loyalty Points',
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildExclusivityNotice(selection),
            const SizedBox(height: 18),
            _buildVoucherSection(selection),
            const SizedBox(height: 22),
            const MrSectionTitle(title: 'Loyalty Points'),
            const SizedBox(height: 6),
            const MrFadeDivider(),
            const SizedBox(height: 14),
            SpendPointsControl(
              points: selection.pointsToSpend,
              enabled: !selection.hasVoucher,
              disabledReason: _pointsBlockedReason(selection),
              onChanged: (value) =>
                  ref.read(discountSelectionProvider.notifier).applyPoints(value),
            ),
          ],
        ),
      ),
    );
  }

  /// States the one-rule-there-is in the customer's own terms, with the way out
  /// of it. Shown only while something is applied, because with nothing applied
  /// there is no rule to explain.
  Widget _buildExclusivityNotice(DiscountSelection selection) {
    if (!selection.hasCustomerChosenSaving) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Use one saving per order — a voucher or your points, not both. '
                'Your welcome offer applies on its own until you choose one here.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textPrimary, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    final isVoucher = selection.hasVoucher;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 18, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isVoucher
                      ? 'Voucher ${selection.voucher!.code} applied.'
                      : 'Applying ${selection.pointsToSpend} of your points.',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isVoucher
                      ? 'Your points are not being used on this order.'
                      : 'Your voucher is not being used on this order.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () {
                      ref.read(discountSelectionProvider.notifier).clear();
                      _showMessage('Removed. You can pick the other one now.');
                    },
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: AppColors.primary,
                    ),
                    child: Text(
                      isVoucher
                          ? 'Remove voucher to use points'
                          : 'Remove points to use a voucher',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The wording shown in place of the points control when a voucher owns the
  /// order, and vice versa.
  String? _pointsBlockedReason(DiscountSelection selection) {
    if (!selection.hasVoucher) return null;
    return 'Voucher ${selection.voucher!.code} is applied, so points cannot be '
        'used on this order. Remove the voucher above to spend points instead.';
  }

  Widget _buildVoucherSection(DiscountSelection selection) {
    final voucher = selection.voucher;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MrSectionTitle(title: 'Voucher Code'),
        const SizedBox(height: 6),
        const MrFadeDivider(),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: voucher != null ? AppColors.success : AppColors.border,
              width: voucher != null ? 1.5 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowSoft,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                Icons.confirmation_number_outlined,
                color: voucher != null ? AppColors.success : AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: voucher != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Code "${voucher.code}" applied!',
                            style: const TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontWeight: FontWeight.w800,
                              color: AppColors.success,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            _describeVoucherSaving(voucher),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      )
                    : TextField(
                        controller: _voucherController,
                        enabled: !selection.hasPoints,
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: (_) => _applyTypedCode(),
                        decoration: InputDecoration(
                          hintText: selection.hasPoints
                              ? 'Remove your points to use a voucher'
                              : 'Enter voucher code',
                          hintStyle: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textLight,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
              ),
              if (voucher != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textLight, size: 20),
                  onPressed: () {
                    ref.read(discountSelectionProvider.notifier).clear();
                    _showMessage('Voucher removed');
                  },
                )
              else
                FilledButton(
                  onPressed:
                      _isCheckingVoucher ? null : () => _applyTypedCode(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    minimumSize: const Size(60, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isCheckingVoucher
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Apply',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Describes the saving in the voucher's own terms, taken from the row the
  /// database returned — never a percentage or amount the app worked out itself.
  String _describeVoucherSaving(VoucherCheck voucher) {
    if (voucher.isFreeDelivery) {
      return 'Free delivery (-Rs. ${voucher.discountAmount.toInt()})';
    }
    final kind = voucher.isPercentage
        ? '${_trimNumber(voucher.discountValue)}% off'
        : 'Rs. ${voucher.discountValue.toInt()} off';
    return '$kind (-Rs. ${voucher.discountAmount.toInt()})';
  }

  /// Drops the zeros Postgres `numeric` carries, so 20.00 reads as "20%" and
  /// 300.00 as "300", instead of leaking the column's scale into the UI.
  String _trimNumber(double value) {
    final text = value.toStringAsFixed(2);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}