import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/wallet.dart';

/// The wallet, held in memory only.
///
/// Nothing here talks to Supabase, and the balance is never assigned directly:
/// it is always the sum of the ledger, so the screen cannot show a number the
/// transactions do not add up to.
class WalletNotifier extends StateNotifier<List<WalletTransaction>> {
  WalletNotifier() : super(_seedHistory());

  /// Smallest top up the screen offers, in rupees.
  static const double minimumTopUp = 100;

  /// Largest single top up, to match a typical card limit.
  static const double maximumTopUp = 25000;

  /// Money in the wallet: the sum of every movement, never a stored number.
  double get balance =>
      state.fold<double>(0, (sum, entry) => sum + entry.signedAmount);

  bool get isEmpty => state.isEmpty;

  /// Adds money after the customer confirms an amount and a payment method.
  ///
  /// Returns false when [amount] is outside the allowed range, so a bad amount
  /// can never enter the ledger.
  bool topUp({required double amount, String method = 'Card'}) {
    if (amount < minimumTopUp || amount > maximumTopUp) return false;
    if (amount.isNaN || amount.isInfinite) return false;

    state = [
      WalletTransaction(
        amount: amount,
        kind: WalletTransactionKind.credit,
        title: 'Wallet top up',
        subtitle: method,
        occurredAt: DateTime.now(),
      ),
      ...state,
    ];
    return true;
  }

  /// Takes money out, for paying for an order.
  ///
  /// Refuses to overdraw, which is the one rule that makes a wallet mean
  /// something. Returns false when there is not enough.
  bool pay({required double amount, required String title, String? subtitle}) {
    if (amount <= 0 || amount.isNaN || amount.isInfinite) return false;
    if (amount > balance) return false;

    state = [
      WalletTransaction(
        amount: amount,
        kind: WalletTransactionKind.debit,
        title: title,
        subtitle: subtitle,
        occurredAt: DateTime.now(),
      ),
      ...state,
    ];
    return true;
  }

  /// A believable starting statement so the screen is not an empty box on first
  /// open, with a real opening balance rather than a fake "bonus".
  static List<WalletTransaction> _seedHistory() {
    final now = DateTime.now();
    return [
      WalletTransaction(
        amount: 2500,
        kind: WalletTransactionKind.credit,
        title: 'Wallet top up',
        subtitle: 'Card ending 4242',
        occurredAt: now.subtract(const Duration(days: 2)),
      ),
      WalletTransaction(
        amount: 1849,
        kind: WalletTransactionKind.debit,
        title: 'Order #MRP-1042',
        subtitle: '2 items, Abbottabad',
        occurredAt: now.subtract(const Duration(days: 1, hours: 3)),
      ),
      WalletTransaction(
        amount: 1500,
        kind: WalletTransactionKind.credit,
        title: 'Wallet top up',
        subtitle: 'Card ending 4242',
        occurredAt: now.subtract(const Duration(hours: 6)),
      ),
    ];
  }
}

final walletProvider =
    StateNotifierProvider<WalletNotifier, List<WalletTransaction>>((ref) {
  return WalletNotifier();
});
