import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/loyalty/models/loyalty.dart';

/// `redeem_loyalty_points` is the only thing that decides what an order costs,
/// and it returns figures that differ from what was asked for. These cases pin
/// the parsing of that response, because getting it wrong does not crash — it
/// shows the customer a saving that never reached the till.
void main() {
  group('a successful redemption is read as the database states it', () {
    test('takes points_spent, discount_applied and new_total verbatim', () {
      final redemption = LoyaltyRedemption.fromRpcResult({
        'ok': true,
        'points_spent': 50,
        'discount_applied': 50,
        'new_total': 1100,
        'balance': 2207,
        'message': 'Spent 50 points and saved Rs. 50.',
      });

      expect(redemption.ok, isTrue);
      expect(redemption.pointsSpent, 50);
      expect(redemption.discountApplied, 50);
      expect(redemption.newTotal, 1100);
      expect(redemption.balance, 2207);
      expect(redemption.message, 'Spent 50 points and saved Rs. 50.');
    });

    test('a clamped spend reports what was spent, not what was requested', () {
      // Asking for 50 on a Rs 30 order spends 30. The request is not evidence.
      final redemption = LoyaltyRedemption.fromRpcResult({
        'ok': true,
        'points_spent': 30,
        'discount_applied': 30,
        'new_total': 0,
        'balance': 970,
        'message': 'Spent 30 points and saved Rs. 30.',
      });

      expect(redemption.ok, isTrue);
      expect(redemption.pointsSpent, 30);
      expect(redemption.balance, 970);
    });

    test('a fractional rupee amount survives as a number', () {
      // Postgres numeric arrives as a JSON number or the same digits quoted.
      final fromNumber = LoyaltyRedemption.fromRpcResult({
        'ok': true,
        'points_spent': 3,
        'discount_applied': 7.5,
        'new_total': 92.5,
        'balance': 97,
      });
      final fromString = LoyaltyRedemption.fromRpcResult({
        'ok': true,
        'points_spent': 3,
        'discount_applied': '7.50',
        'new_total': '92.50',
        'balance': 97,
      });

      expect(fromNumber.discountApplied, 7.5);
      expect(fromNumber.newTotal, 92.5);
      expect(fromString.discountApplied, 7.5);
      expect(fromString.newTotal, 92.5);
    });
  });

  group('every refusal is a refusal', () {
    final refusals = {
      'too many points':
          'You have 100 points available.',
      'already redeemed': 'You have already used points on this order.',
      'wrong customer': 'That is not your order.',
      'voucher took it all': 'This order is already fully discounted.',
      'order too small':
          'You do not have enough points to cover any part of this order.',
      'too late': 'Points can only be spent before an order is delivered.',
      'switched off': 'Loyalty points cannot be spent right now.',
    };

    refusals.forEach((cause, message) {
      test('"$cause" is not treated as a success', () {
        final redemption = LoyaltyRedemption.fromRpcResult({
          'ok': false,
          'message': message,
        });

        expect(redemption.ok, isFalse);
        expect(redemption.message, message);
        // A refusal must not leave numbers a screen could display as a saving.
        expect(redemption.pointsSpent, 0);
        expect(redemption.discountApplied, 0);
      });
    });

    test('a payload missing ok is a refusal, never a win', () {
      // This function debits a real ledger: assuming success would tell the
      // customer they saved money that was never taken off the bill.
      final redemption = LoyaltyRedemption.fromRpcResult({
        'points_spent': 50,
        'discount_applied': 50,
      });

      expect(redemption.ok, isFalse);
      expect(redemption.pointsSpent, 0);
    });

    test('an unreadable payload does not crash and keeps a message', () {
      final redemption = LoyaltyRedemption.fromRpcResult(null);
      expect(redemption.ok, isFalse);
      expect(redemption.message, isNotEmpty);
    });

    test('a refusal with no message still says something', () {
      final redemption = LoyaltyRedemption.fromRpcResult({'ok': false});
      expect(redemption.ok, isFalse);
      expect(redemption.message, isNotEmpty);
    });
  });

  group('a one-row list payload is unwrapped', () {
    test('a wrapped success parses the same as a bare object', () {
      final redemption = LoyaltyRedemption.fromRpcResult([
        {
          'ok': true,
          'points_spent': 25,
          'discount_applied': 25,
          'new_total': 500,
          'balance': 75,
        },
      ]);

      expect(redemption.ok, isTrue);
      expect(redemption.pointsSpent, 25);
    });
  });

  group('balance payload settings drive what can be offered', () {
    LoyaltyBalance balanceWith(Map<String, dynamic>? settings) =>
        LoyaltyBalance.fromRpcResult({
          'ok': true,
          'balance': 100,
          'history': <Object>[],
          'settings': settings,
        });

    test('enabled with a rate allows spending', () {
      final balance = balanceWith({
        'enabled': true,
        'rupees_per_point': 10,
        'redemption_value': 1,
      });
      expect(balance.canSpendPoints, isTrue);
    });

    test('switched off blocks spending even with a balance', () {
      final balance = balanceWith({
        'enabled': false,
        'rupees_per_point': 10,
        'redemption_value': 1,
      });
      expect(balance.canSpendPoints, isFalse);
      // The balance is still real and still shown.
      expect(balance.balance, 100);
    });

    test('missing settings block spending, matching the database', () {
      // With no settings row there is no redemption value, and
      // `redeem_loyalty_points` refuses — so the UI must not offer it.
      expect(balanceWith(null).canSpendPoints, isFalse);
      expect(balanceWith({}).canSpendPoints, isFalse);
    });

    test('enabled but with no redemption rate blocks spending', () {
      expect(
        balanceWith({'enabled': true, 'rupees_per_point': 10}).canSpendPoints,
        isFalse,
      );
    });
  });

  group('history entries are parsed defensively', () {
    test('an empty ledger is an empty list, never null', () {
      final balance = LoyaltyBalance.fromRpcResult({
        'ok': true,
        'balance': 0,
        'history': [],
        'settings': {'enabled': true, 'rupees_per_point': 10},
      });
      expect(balance.history, isEmpty);
    });

    test('a null history is treated as empty', () {
      final balance = LoyaltyBalance.fromRpcResult({
        'ok': true,
        'balance': 0,
        'history': null,
      });
      expect(balance.history, isEmpty);
    });

    test('an unknown entry_type is not mislabelled as a reward', () {
      final balance = LoyaltyBalance.fromRpcResult({
        'ok': true,
        'balance': -10,
        'history': [
          {
            'points': -10,
            'entry_type': 'mystery',
            'reason': 'Adjusted by support',
            'created_at': '2026-10-02T20:51:36.392072+00:00',
          },
        ],
      });

      final entry = balance.history.single;
      expect(entry.type, isNull);
      // Still shown as a deduction, because the sign says so.
      expect(entry.isDeduction, isTrue);
      expect(entry.reason, 'Adjusted by support');
    });

    test('created_at is parsed from the database timestamp', () {
      final balance = LoyaltyBalance.fromRpcResult({
        'ok': true,
        'balance': 2257,
        'history': [
          {
            'points': -50,
            'entry_type': 'redeemed',
            'reason': 'Points spent on order ABT-026',
            'created_at': '2026-10-02T20:51:36.392072+00:00',
            'order_id': '8f3c-aaaa',
          },
        ],
      });

      final entry = balance.history.single;
      expect(entry.createdAt, isNotNull);
      expect(entry.orderId, '8f3c-aaaa');
      expect(balance.entryForOrder('8f3c-aaaa'), same(entry));
      expect(balance.entryForOrder('other-order'), isNull);
    });
  });
}