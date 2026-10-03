import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/supabase_client.dart';
import '../models/loyalty.dart';

/// The customer's loyalty points, read from and spent through the database's own
/// two functions.
///
/// The app owns no balance and no points arithmetic. The balance is a sum of a
/// ledger it cannot read or write, and spending is a single transaction the
/// database performs — debiting the ledger and re-totalling the order together.
/// `loyalty_ledger` has no customer read policy, so `get_my_loyalty_balance()`
/// is the only way in and there is deliberately no other door.
class LoyaltyRepository {
  /// Resolved lazily, mirroring [VoucherRepository]: a test can construct this
  /// without the global Supabase client having been initialised.
  final SupabaseClient? _injectedClient;

  LoyaltyRepository({SupabaseClient? client}) : _injectedClient = client;

  SupabaseClient get client => _injectedClient ?? supabase;

  /// Reads the balance, the last 50 ledger rows and the configured rates.
  ///
  /// Never cached here. Points move whenever an order is delivered or
  /// cancelled, and a stale figure that disagrees with the admin panel is worse
  /// than a second round trip.
  Future<LoyaltyBalance> fetchBalance() async {
    final result = await client.rpc('get_my_loyalty_balance');
    return LoyaltyBalance.fromRpcResult(result);
  }

  /// Spends [points] against [orderId].
  ///
  /// Must run *after* the order row exists — the function locks the order and
  /// reads its real subtotal and current discount back off the row, then works
  /// out what it can actually afford to give. That is why this is called
  /// straight after the order is inserted, in the same place a voucher is
  /// claimed, and never before it.
  ///
  /// The returned [LoyaltyRedemption] is the only source of truth about what
  /// happened. The request may be clamped to less than what was asked for, and a
  /// refusal is a normal outcome rather than an exception.
  Future<LoyaltyRedemption> redeemPoints({
    required String orderId,
    required int points,
  }) async {
    final result = await client.rpc('redeem_loyalty_points', params: {
      'p_order_id': orderId,
      'p_points': points,
    });

    return LoyaltyRedemption.fromRpcResult(result);
  }
}

final loyaltyRepositoryProvider = Provider<LoyaltyRepository>(
  (ref) => LoyaltyRepository(),
);