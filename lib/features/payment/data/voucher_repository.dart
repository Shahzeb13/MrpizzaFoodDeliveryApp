import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/supabase_client.dart';
import '../models/voucher.dart';

/// Everything the checkout screen needs to know about vouchers, taken from the
/// `vouchers` table through the database's own voucher functions.
///
/// The app holds no voucher list and no discount rules of its own. Customers
/// cannot read the `vouchers` table directly (RLS keeps it to staff), and
/// duplicating its rules in Dart would mean two places to keep in step and a
/// way for the app and the ledger to disagree about what an order cost.
class VoucherRepository {
  /// Resolved lazily, mirroring [RiderRepository]: a test can construct this
  /// without the global Supabase client having been initialised.
  final SupabaseClient? _injectedClient;

  VoucherRepository({SupabaseClient? client}) : _injectedClient = client;

  SupabaseClient get client => _injectedClient ?? supabase;

  /// Asks the database whether [code] can be used on a cart worth [subtotal]
  /// that contains [menuItemIds].
  ///
  /// Read-only and safe to call repeatedly while the customer types: nothing is
  /// reserved here, so a code that passes the check can still be taken by
  /// someone else before the order lands. [VoucherRepository.redeemVoucher] is
  /// what actually claims it.
  Future<VoucherCheck> validateVoucher({
    required String code,
    required double subtotal,
    required List<String> menuItemIds,
  }) async {
    final result = await client.rpc('validate_voucher', params: {
      'p_code': code.trim(),
      'p_subtotal': subtotal,
      'p_menu_item_ids': menuItemIds,
    });

    return VoucherCheck.fromRpcResult(result);
  }

  /// Claims [code] against [orderId], recording the redemption and writing the
  /// discount onto the order.
  ///
  /// Must run *after* the order row exists — the function reads the real
  /// subtotal and menu items back off `orders` / `order_items` rather than
  /// trusting the cart, so the discount is always computed from what was
  /// actually ordered. It is also the point at which a voucher that passed
  /// [validateVoucher] can still be refused (expired, or the customer's limit
  /// reached in between), so the returned [VoucherCheck] must be read rather
  /// than assumed to be a success.
  Future<VoucherCheck> redeemVoucher({
    required String code,
    required String orderId,
  }) async {
    final result = await client.rpc('redeem_voucher', params: {
      'p_code': code.trim(),
      'p_order_id': orderId,
    });

    return VoucherCheck.fromRpcResult(result);
  }
}

final voucherRepositoryProvider = Provider<VoucherRepository>(
  (ref) => VoucherRepository(),
);
