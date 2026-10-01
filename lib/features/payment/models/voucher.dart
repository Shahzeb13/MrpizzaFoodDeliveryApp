/// The database's answer to "can this voucher be used on this cart, and what
/// does it take off?".
///
/// Every field is copied straight out of the `jsonb` that the
/// `validate_voucher` and `redeem_voucher` database functions return. No
/// discount rule, expiry, cap or usage limit is ever re-implemented here: the
/// app renders the verdict it is given, including the reason for a refusal, so
/// a customer can never be told a code works when the database disagrees.
class VoucherCheck {
  /// False whenever the database refused the code, or gave no discount.
  final bool isApproved;

  /// The code as the database stores it, not as the customer typed it.
  final String code;

  /// The database's own wording — shown verbatim so a refusal explains itself
  /// ("needs a minimum subtotal of Rs. 2000", "you have already used this").
  final String message;

  final String voucherId;

  /// `percentage`, `fixed` or `free_delivery`, straight from the vouchers table.
  final String discountType;

  final double discountValue;
  final double minOrderAmount;
  final double? maxDiscountAmount;
  final DateTime? validUntil;

  /// True when the voucher is tied to specific menu items through
  /// `voucher_menu_items`, so the whole cart has to qualify.
  final bool isRestrictedToCertainItems;

  /// True for a `free_delivery` voucher, where the discount IS the delivery fee
  /// and the fee line has to be shown as waived rather than as a reduction.
  final bool isFreeDelivery;

  /// What the voucher actually takes off, already capped and floored by the
  /// database. Zero when the code was refused.
  final double discountAmount;

  /// The delivery fee this voucher hands back. Zero for anything that is not a
  /// `free_delivery` voucher.
  final double waivedDeliveryFee;

  const VoucherCheck({
    required this.isApproved,
    required this.code,
    required this.message,
    required this.voucherId,
    required this.discountType,
    required this.discountValue,
    required this.minOrderAmount,
    required this.maxDiscountAmount,
    required this.validUntil,
    required this.isRestrictedToCertainItems,
    required this.isFreeDelivery,
    required this.discountAmount,
    required this.waivedDeliveryFee,
  });

  /// The only state in which this voucher may be counted against an order: the
  /// database approved it for this cart AND it actually saves something.
  bool get isUsable => isApproved && discountAmount > 0;

  /// True when the saving is a percentage of the subtotal, so the UI can say
  /// "20% off" rather than inventing a fixed-amount description.
  bool get isPercentage => discountType == 'percentage';

  bool get isFixedAmount => discountType == 'fixed';

  /// The delivery charge the customer still pays once this voucher is counted.
  double deliveryFeeAfterVoucher(double deliveryFee) =>
      isFreeDelivery ? 0.0 : deliveryFee;

  /// Reads the `jsonb` returned by a voucher database function.
  ///
  /// Tolerant of the two shapes PostgREST can hand back for a single-row
  /// function — the object itself, or a one-element list wrapping it — and of
  /// `numeric` arriving as either a JSON number or a quoted string. Anything
  /// unrecognised becomes a refusal rather than a silent success, because a
  /// voucher the app cannot read must not be treated as usable.
  factory VoucherCheck.fromRpcResult(Object? result) {
    final payload = _unwrapPayload(result);
    if (payload == null) {
      return const VoucherCheck(
        isApproved: false,
        code: '',
        message: 'This voucher code could not be checked. Please try again.',
        voucherId: '',
        discountType: '',
        discountValue: 0,
        minOrderAmount: 0,
        maxDiscountAmount: null,
        validUntil: null,
        isRestrictedToCertainItems: false,
        isFreeDelivery: false,
        discountAmount: 0,
        waivedDeliveryFee: 0,
      );
    }

    final discountAmount = _asDouble(payload['discount_amount']);

    return VoucherCheck(
      isApproved: payload['ok'] == true,
      code: _asString(payload['code']),
      message: _asString(
        payload['message'],
        fallback: 'This voucher could not be applied.',
      ),
      voucherId: _asString(payload['voucher_id']),
      discountType: _asString(payload['discount_type']),
      discountValue: _asDouble(payload['discount_value']),
      minOrderAmount: _asDouble(payload['min_order_amount']),
      maxDiscountAmount: payload['max_discount_amount'] == null
          ? null
          : _asDouble(payload['max_discount_amount']),
      validUntil: DateTime.tryParse(_asString(payload['valid_to'])),
      isRestrictedToCertainItems: payload['scoped'] == true,
      isFreeDelivery: payload['free_delivery'] == true,
      discountAmount: discountAmount,
      waivedDeliveryFee: _asDouble(payload['delivery_fee']),
    );
  }

  static Map<String, dynamic>? _unwrapPayload(Object? result) {
    if (result is Map) return Map<String, dynamic>.from(result);
    if (result is List && result.isNotEmpty && result.first is Map) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    return null;
  }

  static String _asString(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}
