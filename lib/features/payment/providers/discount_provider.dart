import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../loyalty/models/loyalty.dart';
import '../../loyalty/providers/loyalty_provider.dart';
import '../../loyalty/widgets/spend_points_control.dart';
import '../data/voucher_repository.dart';
import '../models/discount.dart';

/// The savings the customer has chosen for this cart.
///
/// Held here rather than on the checkout screen because the voucher and points
/// controls now live on their own page: the page and the cart have to be looking
/// at the same state, or what the customer chose on one screen is missing from
/// the other and the order goes out undiscounted.
final discountSelectionProvider =
    NotifierProvider<DiscountSelectionNotifier, DiscountSelection>(
  DiscountSelectionNotifier.new,
);

/// Keeps at most one saving on an order.
///
/// Every mutation clears the other one. That is deliberate: the database refuses
/// a second saving on an order (`redeem_voucher` and `redeem_loyalty_points`
/// each reject an order that already carries the other), so letting both sit in
/// the app would only produce an order the server then rejects at the last step.
class DiscountSelectionNotifier extends Notifier<DiscountSelection> {
  @override
  DiscountSelection build() => DiscountSelection.empty;

  /// Applies a voucher and drops any points request in the same move.
  void applyVoucher(DiscountSelection voucherSelection) {
    state = DiscountSelection(voucher: voucherSelection.voucher);
  }

  /// Applies a points request and drops any voucher in the same move.
  ///
  /// Zero clears the request rather than setting it, so the "use none" control
  /// needs no special case.
  void applyPoints(int points) {
    state = state.withPoints(points);
  }

  /// Removes whatever is applied, so the customer can switch to the other one.
  void clear() {
    state = DiscountSelection.empty;
  }
}

/// Whether the welcome offer applies to the cart being checked out, keyed on the
/// two things it depends on: what the items come to, and which branch will
/// fulfil the order. Either changing means the offer has to be re-asked, which
/// is why the subtotal is part of the key rather than a parameter read later.
///
/// Returns [FirstOrderOffer.none] before there is a subtotal or a branch, because
/// the database needs both to answer and a guess would be worse than nothing.
final firstOrderOfferProvider = FutureProvider.autoDispose
    .family<FirstOrderOffer, ({double subtotal, String? branchId})>(
  (ref, cart) async {
    if (cart.subtotal <= 0 || cart.branchId == null) {
      return FirstOrderOffer.none;
    }

    return ref.read(voucherRepositoryProvider).fetchFirstOrderOffer(
          subtotal: cart.subtotal,
          branchId: cart.branchId,
        );
  },
);

/// What is on this order right now, as one line the cart can render.
///
/// The welcome offer is automatic and stands aside for anything the customer
/// chose: it is not added on top of a voucher or a points spend, so the customer
/// is never shown a saving that the order will not honour.
///
/// [loyalty] carries the redemption rate, which is read from the customer's
/// branch settings rather than assumed. The points figure it produces is a
/// ceiling for the same reason the points control says "up to": the database
/// clamps the spend once the order exists.
AppliedDiscountSummary? resolvedDiscountSummary({
  required DiscountSelection selection,
  required FirstOrderOffer? firstOrderOffer,
  required LoyaltyBalance loyalty,
}) {
  final voucher = selection.voucher;
  if (voucher != null) {
    return AppliedDiscountSummary(
      label: 'Voucher ${voucher.code}',
      saving: voucher.discountAmount,
    );
  }

  if (selection.hasPoints) {
    final value = loyalty.settings.redemptionValue ?? 0;
    return AppliedDiscountSummary(
      label: '${formatPoints(selection.pointsToSpend)} points',
      saving: selection.pointsToSpend * value,
    );
  }

  final offer = firstOrderOffer;
  if (offer != null && offer.isEligible) {
    return AppliedDiscountSummary(
      label: 'Welcome offer ${offer.percentage}%',
      saving: offer.discountAmount,
      isFirstOrderOffer: true,
    );
  }

  return null;
}

/// The balance that [resolvedDiscountSummary] needs, or a signed-out one when
/// nothing has loaded. Kept as a provider so the cart and the voucher page read
/// the same ledger rather than each taking a snapshot.
///
/// `valueOrNull`, not `value`: a failed balance read must leave the cart showing
/// no points saving rather than throwing while it is being built. The points
/// page still reports the failure in full.
final discountLoyaltyBalanceProvider = Provider<LoyaltyBalance>((ref) {
  return ref.watch(loyaltyBalanceProvider).valueOrNull ??
      LoyaltyBalance.signedOut;
});