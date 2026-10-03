import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/providers/profile_provider.dart';
import '../data/loyalty_repository.dart';
import '../models/loyalty.dart';

/// The signed-in customer's real points balance, with the rates that apply.
///
/// Reads go through `get_my_loyalty_balance()`. This deliberately holds no
/// points counter of its own and no copy of the earn rate: the rate is a setting
/// the admin can change at any moment, so a number held here would be wrong the
/// moment it was written down.
final loyaltyBalanceProvider =
    AsyncNotifierProvider<LoyaltyBalanceNotifier, LoyaltyBalance>(
        LoyaltyBalanceNotifier.new);

class LoyaltyBalanceNotifier extends AsyncNotifier<LoyaltyBalance> {
  @override
  Future<LoyaltyBalance> build() async {
    // Watching the session means signing out or signing in re-reads the balance
    // rather than leaving one customer's points on screen for the next one.
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      // Nothing behind the router asks for a balance while signed out, and the
      // database would refuse anyway. Returning immediately also keeps the
      // startup splash from waiting on a query that cannot succeed.
      return LoyaltyBalance.signedOut;
    }

    return ref.watch(loyaltyRepositoryProvider).fetchBalance();
  }

  /// Re-reads the balance.
  ///
  /// Called after anything that can move points: a redemption, and an order
  /// arriving at `delivered` or `cancelled` — the database credits the first and
  /// automatically refunds the second, and both write a ledger row this app is
  /// not watching.
  Future<void> reload() async {
    state = await AsyncValue.guard(
      () => ref.read(loyaltyRepositoryProvider).fetchBalance(),
    );
  }
}

/// Drops the cached balance so the next reader re-fetches it.
///
/// For the caller that has just changed an order rather than the balance — a
/// branch marking something delivered on another machine, or a cancellation
/// arriving over realtime.
void refreshLoyaltyBalance(WidgetRef ref) {
  ref.invalidate(loyaltyBalanceProvider);
}