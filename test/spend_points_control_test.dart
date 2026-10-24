import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/app_theme.dart';
import 'package:mrpizza/features/loyalty/models/loyalty.dart';
import 'package:mrpizza/features/loyalty/providers/loyalty_provider.dart';
import 'package:mrpizza/features/loyalty/widgets/spend_points_control.dart';
import 'package:mrpizza/features/profile/providers/profile_provider.dart';

/// The stepper used to be the only way to choose a number, so spending 100
/// points meant pressing `+` a hundred times. These cases drive the text field
/// the way a customer does — tap, type, done — and check the figure that comes
/// out, including the two ways it can go wrong: more than the balance, and a
/// field left half-typed.
class _FixedBalance extends LoyaltyBalanceNotifier {
  _FixedBalance(this.value);

  final LoyaltyBalance value;

  @override
  Future<LoyaltyBalance> build() async => value;
}

LoyaltyBalance _balance(int points) => LoyaltyBalance(
      isSignedIn: true,
      balance: points,
      history: const [],
      settings: const LoyaltySettings(
        enabled: true,
        rupeesPerPoint: 10,
        redemptionValue: 1,
      ),
    );

/// Hosts the control the way checkout does, and records what it emits.
Future<int> pumpControl(
  WidgetTester tester, {
  required int balance,
  int initial = 0,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final emitted = <int>[];
  var current = initial;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('customer-1'),
        loyaltyBalanceProvider.overrideWith(() => _FixedBalance(_balance(balance))),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setInner) => SpendPointsControl(
              points: current,
              onChanged: (value) {
                emitted.add(value);
                setInner(() => current = value);
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return current;
}

void main() {
  group('the number can be typed instead of tapped', () {
    testWidgets('typing 100 spends 100, not one hundred taps', (tester) async {
      await pumpControl(tester, balance: 2257);

      final field = find.byType(TextField);
      expect(field, findsOneWidget);

      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '100');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // The committed figure is reflected back up to checkout.
      expect(find.textContaining('100 points'), findsOneWidget);
      expect(find.textContaining('100'), findsWidgets);
    });

    testWidgets('the field holds what was typed', (tester) async {
      await pumpControl(tester, balance: 2257);

      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '250');
      await tester.pump();

      expect(
        tester.widget<TextField>(field).controller?.text,
        '250',
      );
    });

    testWidgets('the buttons still nudge it by one', (tester) async {
      await pumpControl(tester, balance: 2257);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(find.textContaining('1 points'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pumpAndSettle();

      expect(find.text('None selected'), findsOneWidget);
    });

    testWidgets('Use all fills the whole balance in one tap', (tester) async {
      await pumpControl(tester, balance: 2257);

      await tester.tap(find.text('Use all'));
      await tester.pumpAndSettle();

      expect(find.textContaining('2,257 points'), findsOneWidget);
    });
  });

  group('a typed number is clamped to the balance', () {
    testWidgets('asking for more than the balance lands on the balance',
        (tester) async {
      await pumpControl(tester, balance: 500);

      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '999999');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.textContaining('500 points'), findsOneWidget);
    });

    testWidgets('a non-numeric field is rejected at the keyboard',
        (tester) async {
      await pumpControl(tester, balance: 500);

      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, 'abc');
      await tester.pump();

      // `digitsOnly` never lets the letters reach the controller.
      expect(tester.widget<TextField>(field).controller?.text, '');
      expect(find.text('None selected'), findsOneWidget);
    });

    testWidgets('an emptied field counts as nothing rather than an error',
        (tester) async {
      await pumpControl(tester, balance: 500);

      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('None selected'), findsOneWidget);
    });
  });

  group('the saving is a ceiling, never a computed total', () {
    testWidgets('the wording stays "up to" whatever is typed', (tester) async {
      await pumpControl(tester, balance: 2257);

      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '100');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.textContaining('up to'), findsOneWidget);
      // The control states a ceiling only. It must not present a final order
      // total, because the database has not re-totalled the order yet.
      expect(find.textContaining('Total'), findsNothing);
      expect(find.textContaining('You save'), findsNothing);
    });
  });
}