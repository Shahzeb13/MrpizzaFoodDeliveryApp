import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Loyalty points held in the app for the current session.
///
/// Still a local counter: the real balance lives in the `loyalty_ledger` table
/// and nothing in the app reads or writes it yet, so the opening figure is a
/// placeholder rather than a customer's actual balance. It is kept here on its
/// own because the order flow it used to hang off — a list of invented orders
/// that awarded points on a fake "delivered" status — is gone.
class LoyaltyPointsNotifier extends StateNotifier<int> {
  LoyaltyPointsNotifier() : super(0);

  void addPoints(int points) {
    state = state + points;
  }

  void deductPoints(int points) {
    state = (state - points).clamp(0, 999999);
  }
}

final loyaltyPointsProvider =
    StateNotifierProvider<LoyaltyPointsNotifier, int>((ref) {
  return LoyaltyPointsNotifier();
});
