import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/profile/models/wallet.dart';
import 'package:mrpizza/features/profile/providers/wallet_provider.dart';

/// The old screen kept a `balance` field and did `balance += amount` when a
/// quick-top-up button was tapped, so one tap printed free money. The balance is
/// now always the sum of the ledger, and money can also leave.
void main() {
  group('the balance is derived, never stored', () {
    test('starts from the sum of its opening statement', () {
      final wallet = WalletNotifier();

      // 2500 credited, 1849 paid, 1500 credited.
      expect(wallet.balance, 2151);
    });

    test('a top up raises the balance by exactly that amount', () {
      final wallet = WalletNotifier();
      final before = wallet.balance;

      final accepted = wallet.topUp(amount: 1000);

      expect(accepted, isTrue);
      expect(wallet.balance, before + 1000);
    });

    test('a payment lowers the balance by exactly that amount', () {
      final wallet = WalletNotifier();
      final before = wallet.balance;

      final paid = wallet.pay(amount: 151, title: 'Order #MRP-2000');

      expect(paid, isTrue);
      expect(wallet.balance, before - 151);
    });

    test('the balance always equals the sum of the ledger', () {
      final wallet = WalletNotifier()..topUp(amount: 750);

      final summed =
          wallet.state.fold<double>(0, (sum, e) => sum + e.signedAmount);

      expect(wallet.balance, summed);
    });
  });

  group('money only moves through a real transaction', () {
    test('a top up is recorded as the newest entry', () {
      final wallet = WalletNotifier();

      wallet.topUp(amount: 500, method: 'JazzCash');

      expect(wallet.state.first.kind, WalletTransactionKind.credit);
      expect(wallet.state.first.amount, 500);
      expect(wallet.state.first.subtitle, 'JazzCash');
      expect(wallet.state.length, 4);
    });

    test('a payment is recorded as a debit, never a credit', () {
      final wallet = WalletNotifier();

      wallet.pay(amount: 100, title: 'Order #MRP-1');

      final entry = wallet.state.first;
      expect(entry.kind, WalletTransactionKind.debit);
      expect(entry.signedAmount, -100);
      expect(entry.isCredit, isFalse);
    });
  });

  group('the wallet refuses nonsense', () {
    test('will not overdraw', () {
      final wallet = WalletNotifier();

      final paid = wallet.pay(amount: 999999, title: 'Order');

      expect(paid, isFalse);
      expect(wallet.balance, 2151);
      expect(wallet.state.length, 3);
    });

    test('rejects a top up below the minimum', () {
      final wallet = WalletNotifier();
      final before = wallet.balance;

      expect(wallet.topUp(amount: 10), isFalse);
      expect(wallet.balance, before);
    });

    test('rejects a top up above the maximum', () {
      final wallet = WalletNotifier();

      expect(wallet.topUp(amount: 500000), isFalse);
    });

    test('rejects a zero or negative payment', () {
      final wallet = WalletNotifier();

      expect(wallet.pay(amount: 0, title: 'Order'), isFalse);
      expect(wallet.pay(amount: -50, title: 'Order'), isFalse);
    });

    test('rejects NaN so a broken amount cannot poison the sum', () {
      final wallet = WalletNotifier();
      final before = wallet.balance;

      expect(wallet.topUp(amount: double.nan), isFalse);
      expect(wallet.balance, before);
    });
  });

  group('formatting', () {
    test('groups thousands and always shows two decimals', () {
      expect(formatRupees(0), '0.00');
      expect(formatRupees(500), '500.00');
      expect(formatRupees(1250.5), '1,250.50');
      expect(formatRupees(1234567.891), '1,234,567.89');
    });

    test('a credit shows a plus and a debit shows a minus', () {
      final credit = WalletTransaction(
        amount: 500,
        kind: WalletTransactionKind.credit,
        title: 'Top up',
        occurredAt: DateTime(2026, 9, 26),
      );
      final debit = WalletTransaction(
        amount: 1250,
        kind: WalletTransactionKind.debit,
        title: 'Order',
        occurredAt: DateTime(2026, 9, 26),
      );

      expect(credit.signedLabel, '+500.00');
      expect(debit.signedLabel, '-1,250.00');
    });

    test('reads as a statement date', () {
      expect(
        formatWalletTimestamp(DateTime(2026, 9, 26, 20, 42)),
        '26 Sep, 8:42 PM',
      );
      expect(
        formatWalletTimestamp(DateTime(2026, 9, 6, 0, 5)),
        '6 Sep, 12:05 AM',
      );
    });
  });
}
