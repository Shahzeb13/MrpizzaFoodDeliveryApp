import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/app_theme.dart';
import 'package:mrpizza/features/loyalty/models/loyalty.dart';
import 'package:mrpizza/features/loyalty/providers/loyalty_provider.dart';
import 'package:mrpizza/features/profile/providers/profile_provider.dart';
import 'package:mrpizza/features/profile/screens/loyalty_points_screen.dart';

/// These tests exist because the previous screen invented everything it showed:
/// an opening balance of 120, a hardcoded "Earn 1 point on every Rs. 10", and a
/// set of rewards that deducted points and handed back nothing. The cases below
/// pin the real contract — the rate is read from `settings`, a deduction never
/// looks like a reward, a refusal is a refusal — so none of that can creep back
/// in as a hardcoded string.
LoyaltyBalance _balance({
  int points = 2257,
  bool enabled = true,
  double rupeesPerPoint = 10,
  double redemptionValue = 1,
  List<LoyaltyEntry> history = const [],
}) {
  return LoyaltyBalance(
    isSignedIn: true,
    balance: points,
    history: history,
    settings: LoyaltySettings(
      enabled: enabled,
      rupeesPerPoint: rupeesPerPoint,
      redemptionValue: redemptionValue,
    ),
  );
}

/// Serves a fixed balance without touching Supabase or the auth chain, which
/// the real notifier follows to decide whose points to read.
class _FixedBalance extends LoyaltyBalanceNotifier {
  _FixedBalance(this.value);

  final LoyaltyBalance value;

  @override
  Future<LoyaltyBalance> build() async => value;
}

Future<void> pumpScreen(
  WidgetTester tester, {
  LoyaltyBalance? balance,
  Size surface = const Size(360, 900),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('customer-1'),
        loyaltyBalanceProvider.overrideWith(
          () => _FixedBalance(balance ?? _balance()),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const LoyaltyPointsScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('the earn rate is read from settings, never hardcoded', () {
    testWidgets('a divisor of 10 reads "every Rs 10"', (tester) async {
      await pumpScreen(tester, balance: _balance(rupeesPerPoint: 10));
      expect(
        find.text('EARN 1 POINT FOR EVERY RS 10'),
        findsOneWidget,
      );
    });

    testWidgets('a divisor of 100 reads "every Rs 100"', (tester) async {
      await pumpScreen(tester, balance: _balance(rupeesPerPoint: 100));
      expect(
        find.text('EARN 1 POINT FOR EVERY RS 100'),
        findsOneWidget,
      );
    });

    testWidgets('a divisor of 1 reads "every Rs 1", not "Rs 10"',
        (tester) async {
      await pumpScreen(tester, balance: _balance(rupeesPerPoint: 1));
      expect(find.text('EARN 1 POINT FOR EVERY RS 1'), findsOneWidget);
      // The old string, which must not survive a settings change.
      expect(find.textContaining('RS 10'), findsNothing);
    });

    test('the label follows whatever the admin set', () {
      LoyaltySettings settingsFor(double rate) => LoyaltySettings(
            enabled: true,
            rupeesPerPoint: rate,
            redemptionValue: 1,
          );

      expect(settingsFor(10).earnRateLabel,
          'Earn 1 point for every Rs 10');
      expect(settingsFor(1).earnRateLabel, 'Earn 1 point for every Rs 1');
      expect(settingsFor(100).earnRateLabel, 'Earn 1 point for every Rs 100');
      // A fractional rate stays readable rather than printing "Rs 7.50".
      expect(settingsFor(7.5).earnRateLabel, 'Earn 1 point for every Rs 7.5');
    });

    test('an unconfigured rate produces no label rather than a guess', () {
      expect(LoyaltySettings.unknown.earnRateLabel, isNull);
      expect(
        const LoyaltySettings(
          enabled: true,
          rupeesPerPoint: 0,
          redemptionValue: 1,
        ).earnRateLabel,
        isNull,
      );
    });
  });

  group('the balance is what the ledger says', () {
    testWidgets('shows the real balance', (tester) async {
      await pumpScreen(tester, balance: _balance(points: 2257));
      expect(find.text('2,257'), findsOneWidget);
    });

    testWidgets('a signed-out read shows no balance and no raw error',
        (tester) async {
      await pumpScreen(tester, balance: LoyaltyBalance.signedOut);

      expect(find.text('0'), findsOneWidget);
      // The database's own "Sign in to see your loyalty points." must never be
      // surfaced as an error string.
      expect(find.textContaining('Sign in'), findsNothing);
    });

    test('the refused payload is not mistaken for a zero balance', () {
      final balance = LoyaltyBalance.fromRpcResult({
        'ok': false,
        'message': 'Sign in to see your loyalty points.',
      });
      expect(balance.isSignedIn, isFalse);
    });

    test('a payload missing ok is a refusal, not a success', () {
      final balance = LoyaltyBalance.fromRpcResult({'balance': 500});
      expect(balance.isSignedIn, isFalse);
      expect(balance.balance, 0);
    });
  });

  group('a deduction never looks like a reward', () {
    LoyaltyEntry spent(int points) => LoyaltyEntry(
          points: -points,
          type: LoyaltyEntryType.redeemed,
          reason: 'Points spent on order ABT-026',
          createdAt: DateTime(2026, 10, 2),
          orderId: 'order-1',
        );

    test('the sign and the entry type are read from the ledger row', () {
      final entry = spent(50);
      expect(entry.isDeduction, isTrue);
      expect(entry.type, LoyaltyEntryType.redeemed);
      expect(entry.reason, 'Points spent on order ABT-026');
    });

    test('a positive reversed row is not counted as a spend', () {
      const entry = LoyaltyEntry(
        points: 50,
        type: LoyaltyEntryType.reversed,
        reason: 'Order cancelled',
        createdAt: null,
        orderId: 'order-1',
      );
      expect(entry.isDeduction, isFalse);
      expect(entry.type, LoyaltyEntryType.reversed);
    });

    testWidgets('a spent row shows a minus and never a plus', (tester) async {
      await pumpScreen(
        tester,
        balance: _balance(history: [spent(50)]),
      );

      expect(find.text('-50'), findsOneWidget);
      expect(find.text('+50'), findsNothing);
    });

    testWidgets('an earned row shows a plus', (tester) async {
      await pumpScreen(
        tester,
        balance: _balance(
          history: const [
            LoyaltyEntry(
              points: 250,
              type: LoyaltyEntryType.earned,
              reason: 'Points earned on order ABT-025',
              createdAt: null,
              orderId: 'order-2',
            ),
          ],
        ),
      );

      expect(find.text('+250'), findsOneWidget);
    });
  });

  group('an empty ledger is a normal state, not a failure', () {
    testWidgets('leads with the earn rate instead of an apology',
        (tester) async {
      await pumpScreen(tester, balance: _balance(points: 0));

      expect(find.text('EARN 1 POINT FOR EVERY RS 10'), findsOneWidget);
      expect(find.textContaining('delivered'), findsOneWidget);
    });
  });

  group('the deleted rewards list cannot come back', () {
    testWidgets('nothing offers to redeem points for a cold drink',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('Redeem Rewards'), findsNothing);
      expect(find.textContaining('Cold Drink'), findsNothing);
      expect(find.textContaining('Garlic Bread'), findsNothing);
      expect(find.textContaining('Points Required'), findsNothing);
    });
  });

  group('points earned on a specific order come from the ledger', () {
    test('reads the earned row rather than recomputing from the total', () {
      final balance = _balance(
        history: const [
          LoyaltyEntry(
            points: 120,
            type: LoyaltyEntryType.earned,
            reason: 'Points earned on order ABT-027',
            createdAt: null,
            orderId: 'order-27',
          ),
          LoyaltyEntry(
            points: -40,
            type: LoyaltyEntryType.redeemed,
            reason: 'Points spent on order ABT-027',
            createdAt: null,
            orderId: 'order-27',
          ),
        ],
      );

      expect(balance.pointsEarnedOnOrder('order-27'), 120);
      expect(balance.pointsSpentOnOrder('order-27'), 40);
      expect(balance.pointsEarnedOnOrder('order-99'), 0);
    });
  });
}