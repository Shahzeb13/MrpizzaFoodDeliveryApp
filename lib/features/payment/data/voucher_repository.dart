import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/supabase_client.dart';
import '../models/discount.dart';
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
  ///
  /// [branchId] is the branch that will fulfil the order. It only matters for a
  /// free-delivery voucher, where the database needs to know which branch's
  /// delivery fee is being waived.
  Future<VoucherCheck> validateVoucher({
    required String code,
    required double subtotal,
    required List<String> menuItemIds,
    String? branchId,
  }) async {
    final result = await client.rpc('validate_voucher', params: {
      'p_code': code.trim(),
      'p_subtotal': subtotal,
      'p_menu_item_ids': menuItemIds,
      // `validate_voucher` takes a user, and PostgREST cannot resolve a
      // function whose required parameters are missing — it answers PGRST202
      // "could not find the function", which the app used to show as "we could
      // not check that code". The parameter has to be in the request even when
      // it carries no value of its own.
      //
      // It is sent as null on purpose: the function then falls back to
      // `auth.uid()`, so the customer is taken from the signed-in token and
      // cannot ask how many times somebody else's voucher has been used.
      'p_user_id': null,
      if (branchId != null) 'p_branch_id': branchId,
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

  /// Asks the database whether the first-order welcome offer applies to a cart
  /// worth [subtotal] being delivered by [branchId], and what it would take off.
  ///
  /// Read-only. Nothing is reserved and nothing is written: this exists so the
  /// cart can show the customer what they are getting before they commit.
  /// [applyFirstOrderDiscount] is what actually puts it on the order, and it
  /// recomputes the figure server-side from the inserted rows.
  Future<FirstOrderOffer> fetchFirstOrderOffer({
    required double subtotal,
    String? branchId,
  }) async {
    final result = await client.rpc('first_order_offer', params: {
      'p_subtotal': subtotal,
      if (branchId != null) 'p_branch_id': branchId,
    });

    return FirstOrderOffer.fromRpcResult(result);
  }

  /// Claims the first-order welcome offer against [orderId], writing the
  /// discount onto the order.
  ///
  /// Runs after the order row exists, for the same reason
  /// [redeemVoucher] does: the amount is computed by the database from the
  /// `orders` / `order_items` rows that were actually inserted, so a modified
  /// client cannot inflate it and cannot claim the offer twice. The function
  /// also refuses an order that already carries a voucher or points discount —
  /// only one saving is ever allowed on an order, and the database is where that
  /// is decided.
  Future<FirstOrderOffer> applyFirstOrderDiscount({
    required String orderId,
  }) async {
    final result = await client.rpc('apply_first_order_discount', params: {
      'p_order_id': orderId,
    });

    return FirstOrderOffer.fromRpcResult(result);
  }
}

final voucherRepositoryProvider = Provider<VoucherRepository>(
  (ref) => VoucherRepository(),
);
