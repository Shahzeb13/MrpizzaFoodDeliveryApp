import 'voucher.dart';

/// Which of the two customer-chosen savings is on this order.
///
/// The app keeps at most one of these at a time, and so does the database:
/// `redeem_voucher` refuses an order that already carries a points discount and
/// `redeem_loyalty_points` refuses one that already carries a voucher. The enum
/// exists so the UI can say *which* one is in force and switch between them,
/// rather than the customer working it out from two independent controls.
enum CustomerDiscountKind { none, voucher, loyaltyPoints }

/// The first-order welcome offer, as the database computed it.
///
/// Read-only: it says whether the offer applies to this cart and what it would
/// take off. Nothing here is written anywhere — `apply_first_order_discount`
/// recomputes the same figure server-side from the order rows, because the
/// amount that ends up on the order is the one Postgres decides, never the one
/// a client displayed earlier.
class FirstOrderOffer {
  /// True only when the database said yes. False covers every refusal: branch
  /// has no settings, offer switched off, customer not signed in, not a first
  /// order, or subtotal under the minimum.
  final bool isEligible;

  /// What the offer takes off, already capped by `first_order_max_cap` and
  /// floored at the subtotal. Zero when not eligible.
  final double discountAmount;

  /// `first_order_discount_pct` for the fulfilling branch. Zero when the
  /// database sent nothing readable.
  final int percentage;

  final double minOrderAmount;
  final double maxDiscountAmount;

  /// The database's own wording, so a refusal explains itself.
  final String message;

  const FirstOrderOffer({
    required this.isEligible,
    required this.discountAmount,
    required this.percentage,
    required this.minOrderAmount,
    required this.maxDiscountAmount,
    required this.message,
  });

  /// "No offer" — what a customer gets before the branch settings are read, and
  /// what a signed-out customer gets.
  static const FirstOrderOffer none = FirstOrderOffer(
    isEligible: false,
    discountAmount: 0,
    percentage: 0,
    minOrderAmount: 0,
    maxDiscountAmount: 0,
    message: '',
  );

  /// Reads the `jsonb` from `first_order_offer`. An unreadable payload becomes
  /// "no offer" rather than a guess, so a broken response can never turn into a
  /// discount the customer was shown but the till never honoured.
  factory FirstOrderOffer.fromRpcResult(Object? result) {
    final payload = _unwrap(result);
    if (payload == null) return none;

    final eligible = payload['ok'] == true;
    final amount = _asDouble(payload['discount_amount']);
    final percentage = _asInt(payload['discount_percentage']);

    // Eligible but worth nothing is not an offer. The database already refuses
    // that case; the extra guard keeps a hand-edited response from becoming one.
    if (!eligible || percentage <= 0 || amount <= 0) {
      return FirstOrderOffer(
        isEligible: false,
        discountAmount: 0,
        percentage: 0,
        minOrderAmount: _asDouble(payload['min_order_amount']),
        maxDiscountAmount: _asDouble(payload['max_discount_amount']),
        message: _asString(payload['message']),
      );
    }

    return FirstOrderOffer(
      isEligible: true,
      discountAmount: amount,
      percentage: percentage,
      minOrderAmount: _asDouble(payload['min_order_amount']),
      maxDiscountAmount: _asDouble(payload['max_discount_amount']),
      message: _asString(payload['message']),
    );
  }

  static Map<String, dynamic>? _unwrap(Object? result) {
    if (result is Map) return Map<String, dynamic>.from(result);
    if (result is List && result.isNotEmpty && result.first is Map) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    return null;
  }

  static String _asString(Object? value) => value?.toString().trim() ?? '';

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

/// The savings the customer has chosen, held for the cart rather than for one
/// screen.
///
/// This lives in a provider rather than in checkout's `setState` because the
/// voucher and points controls moved to their own page: local widget state died
/// with the screen that owned it, so anything chosen on the voucher page would
/// have been forgotten by the time the customer pressed Confirm on the cart.
///
/// Only one of the two is ever non-null. [applyVoucher] clears the points and
/// [applyPoints] clears the voucher, so the exclusivity is a property of the
/// state rather than something each caller has to remember.
class DiscountSelection {
  /// The voucher's whole database verdict, not a code and a number, so the
  /// summary can describe what was actually granted.
  final VoucherCheck? voucher;

  /// How many points the customer asked to spend.
  ///
  /// A request, not a grant: `redeem_loyalty_points` clamps it to what the
  /// order can absorb and rounds down to whole points, and only its answer
  /// decides what the order is worth.
  final int pointsToSpend;

  const DiscountSelection({this.voucher, this.pointsToSpend = 0});

  static const DiscountSelection empty = DiscountSelection();

  bool get hasVoucher => voucher != null;

  bool get hasPoints => pointsToSpend > 0;

  bool get hasCustomerChosenSaving => hasVoucher || hasPoints;

  CustomerDiscountKind get kind {
    if (hasVoucher) return CustomerDiscountKind.voucher;
    if (hasPoints) return CustomerDiscountKind.loyaltyPoints;
    return CustomerDiscountKind.none;
  }

  DiscountSelection withVoucher(VoucherCheck applied) =>
      DiscountSelection(voucher: applied);

  DiscountSelection withPoints(int points) => points > 0
      ? DiscountSelection(pointsToSpend: points)
      : DiscountSelection.empty;
}

/// One line describing what is applied and what it saves, for the cart summary.
///
/// Built in one place so the cart line and the voucher page cannot disagree
/// about what is on the order or how much it is worth.
class AppliedDiscountSummary {
  /// Shown as the discount row label: `Voucher SUPERPIZZA20`,
  /// `1,250 points`, or `Welcome offer`.
  final String label;

  /// What it takes off, as a positive rupees figure.
  final double saving;

  /// True for the welcome offer, which is automatic rather than chosen, and so
  /// has nothing to remove.
  final bool isFirstOrderOffer;

  const AppliedDiscountSummary({
    required this.label,
    required this.saving,
    this.isFirstOrderOffer = false,
  });
}