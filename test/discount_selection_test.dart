import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/loyalty/models/loyalty.dart';
import 'package:mrpizza/features/payment/models/discount.dart';
import 'package:mrpizza/features/payment/models/voucher.dart';
import 'package:mrpizza/features/payment/providers/discount_provider.dart';

/// An order carries one saving. The database decides that — `redeem_voucher` and
/// `redeem_loyalty_points` each refuse an order that already carries the other,
/// and `apply_first_order_discount` refuses both — so if the app ever let both
/// sit in its state, the customer would fill in a voucher, choose points, press
/// Confirm, and have the second one rejected at the last step with the first one
/// already spent. These cases pin the app half of that rule.

VoucherCheck voucherFor(String code, double amount) => VoucherCheck(
      isApproved: true,
      code: code,
      message: 'Voucher applied - Rs. $code off.',
      voucherId: 'voucher-$code',
      discountType: 'percentage',
      discountValue: 15,
      minOrderAmount: 500,
      maxDiscountAmount: 300,
      validUntil: null,
      isRestrictedToCertainItems: false,
      isFreeDelivery: false,
      discountAmount: amount,
      waivedDeliveryFee: 0,
    );

LoyaltyBalance ledgerWith(int points, {double redemptionValue = 1}) =>
    LoyaltyBalance(
      isSignedIn: true,
      balance: points,
      history: const [],
      settings: LoyaltySettings(
        enabled: true,
        rupeesPerPoint: 10,
        redemptionValue: redemptionValue,
      ),
    );

ProviderContainer container() => ProviderContainer();

void main() {
  group('only one saving is ever selected', () {
    test('a voucher replaces any points already requested', () {
      final c = container();
      addTearDown(c.dispose);

      c.read(discountSelectionProvider.notifier).applyPoints(500);
      expect(c.read(discountSelectionProvider).hasPoints, isTrue);

      c.read(discountSelectionProvider.notifier)
          .applyVoucher(DiscountSelection(voucher: voucherFor('BUR15', 150)));

      final selection = c.read(discountSelectionProvider);
      expect(selection.hasVoucher, isTrue);
      expect(selection.hasPoints, isFalse,
          reason: 'points must not survive a voucher being applied');
      expect(selection.kind, CustomerDiscountKind.voucher);
    });

    test('points replace any voucher already applied', () {
      final c = container();
      addTearDown(c.dispose);

      c.read(discountSelectionProvider.notifier)
          .applyVoucher(DiscountSelection(voucher: voucherFor('BUR15', 150)));

      c.read(discountSelectionProvider.notifier).applyPoints(250);

      final selection = c.read(discountSelectionProvider);
      expect(selection.hasPoints, isTrue);
      expect(selection.hasVoucher, isFalse,
          reason: 'the voucher must not survive points being requested');
      expect(selection.kind, CustomerDiscountKind.loyaltyPoints);
    });

    test('zero points clears rather than switching off', () {
      final c = container();
      addTearDown(c.dispose);

      c.read(discountSelectionProvider.notifier).applyPoints(250);
      c.read(discountSelectionProvider.notifier).applyPoints(0);

      expect(c.read(discountSelectionProvider).hasCustomerChosenSaving, isFalse);
    });

    test('clearing leaves nothing behind to be claimed later', () {
      final c = container();
      addTearDown(c.dispose);

      c.read(discountSelectionProvider.notifier)
          .applyVoucher(DiscountSelection(voucher: voucherFor('BUR15', 150)));
      c.read(discountSelectionProvider.notifier).clear();

      expect(c.read(discountSelectionProvider), DiscountSelection.empty);
    });
  });

  group('the summary the cart renders', () {
    test('describes the voucher in its own terms', () {
      final summary = resolvedDiscountSummary(
        selection: DiscountSelection(voucher: voucherFor('BUR15', 150)),
        firstOrderOffer: const FirstOrderOffer(
          isEligible: true,
          discountAmount: 300,
          percentage: 15,
          minOrderAmount: 1000,
          maxDiscountAmount: 300,
          message: 'Welcome offer.',
        ),
        loyalty: ledgerWith(500),
      );

      expect(summary!.label, 'Voucher BUR15');
      expect(summary.saving, 150);
    });

    test('reads the points saving off the branch redemption rate', () {
      final summary = resolvedDiscountSummary(
        selection: const DiscountSelection(pointsToSpend: 250),
        firstOrderOffer: null,
        loyalty: ledgerWith(500, redemptionValue: 1.5),
      );

      expect(summary!.label, '250 points');
      expect(summary.saving, 375,
          reason: '250 points at Rs 1.50 each — the rate comes from settings');
    });

    test('groups a four-figure points figure', () {
      final summary = resolvedDiscountSummary(
        selection: const DiscountSelection(pointsToSpend: 2257),
        firstOrderOffer: null,
        loyalty: ledgerWith(2257),
      );

      expect(summary!.label, '2,257 points');
    });

    test('the welcome offer applies only when nothing was chosen', () {
      final offer = FirstOrderOffer.fromRpcResult({
        'ok': true,
        'discount_amount': 300,
        'discount_percentage': 15,
        'min_order_amount': 1000,
        'max_discount_amount': 300,
        'message': 'Welcome offer.',
      });

      final chosen = resolvedDiscountSummary(
        selection: const DiscountSelection(pointsToSpend: 100),
        firstOrderOffer: offer,
        loyalty: ledgerWith(500),
      );
      expect(chosen!.label, '100 points');
      expect(chosen.isFirstOrderOffer, isFalse);

      final unchosen = resolvedDiscountSummary(
        selection: DiscountSelection.empty,
        firstOrderOffer: offer,
        loyalty: ledgerWith(500),
      );
      expect(unchosen!.label, 'Welcome offer 15%');
      expect(unchosen.saving, 300);
      expect(unchosen.isFirstOrderOffer, isTrue);
    });

    test('a refused offer produces no summary line at all', () {
      final offer = FirstOrderOffer.fromRpcResult({
        'ok': false,
        'discount_amount': 0,
        'message': 'Welcome offer is for first-time orders only.',
      });

      expect(
        resolvedDiscountSummary(
          selection: DiscountSelection.empty,
          firstOrderOffer: offer,
          loyalty: ledgerWith(500),
        ),
        isNull,
      );
    });
  });

  group('reading the offer the database sent', () {
    test('a refusal never becomes a discount', () {
      final offer = FirstOrderOffer.fromRpcResult({
        'ok': false,
        'discount_amount': 0,
        'message': 'Welcome offer is unavailable.',
      });

      expect(offer.isEligible, isFalse);
      expect(offer.discountAmount, 0);
      expect(offer.message, 'Welcome offer is unavailable.');
    });

    test('ok with no percentage is not an offer', () {
      final offer = FirstOrderOffer.fromRpcResult({
        'ok': true,
        'discount_amount': 300,
        'discount_percentage': 0,
        'message': 'Welcome offer.',
      });

      expect(offer.isEligible, isFalse);
      expect(offer.discountAmount, 0);
    });

    test('numeric sent as a quoted string parses the same', () {
      final offer = FirstOrderOffer.fromRpcResult({
        'ok': true,
        'discount_amount': '300.00',
        'discount_percentage': '15',
        'message': 'Welcome offer.',
      });

      expect(offer.discountAmount, 300);
      expect(offer.percentage, 15);
      expect(offer.isEligible, isTrue);
    });

    test('a one-row list unwraps like the bare object', () {
      final offer = FirstOrderOffer.fromRpcResult([
        {'ok': true, 'discount_amount': 300, 'discount_percentage': 15},
      ]);

      expect(offer.discountAmount, 300);
      expect(offer.isEligible, isTrue);
    });

    test('an unreadable payload grants nothing', () {
      for (final payload in <Object?>[null, 'nonsense', <Object?>[]]) {
        expect(FirstOrderOffer.fromRpcResult(payload).isEligible, isFalse,
            reason: 'payload: $payload');
      }
    });
  });
}