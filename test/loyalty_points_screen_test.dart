import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/app_theme.dart';
import 'package:mrpizza/features/profile/screens/loyalty_points_screen.dart';

/// The reward pills used to sit inside a SizedBox(height: 40) while the
/// app-wide button style asks for a 52dp pill with 15dp of vertical padding.
/// The tight box won, so the label's text box was starved to 10dp for a 21dp
/// line and Flutter clipped the words: 'Redeem' was sliced in half and
/// 'Locked' was a ghost.
void main() {
  Future<void> pumpLoyaltyScreen(
    WidgetTester tester, {
    Size surface = const Size(360, 800),
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LoyaltyPointsScreen()),
    );
    await tester.pumpAndSettle();
  }

  /// The height one line of the pill label needs, taken from the theme that
  /// paints it (labelLarge: 15dp at height 1.4, so 21dp).
  double oneLineOfLabelHeight(WidgetTester tester, Finder label) {
    final style = Theme.of(tester.element(label)).textTheme.labelLarge!;
    return style.fontSize! * style.height!;
  }

  group('the reward pills never squash their own label', () {
    testWidgets('Redeem gets a full line to draw in', (tester) async {
      await pumpLoyaltyScreen(tester);

      final label = find.text('Redeem');
      expect(label, findsOneWidget);

      // A starved label renders about 10dp tall; a real one is a whole line.
      expect(
        tester.getSize(label).height,
        greaterThanOrEqualTo(oneLineOfLabelHeight(tester, label) - 1),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('both Locked pills get a full line too', (tester) async {
      await pumpLoyaltyScreen(tester);

      final locked = find.text('Locked');
      expect(locked, findsNWidgets(2));

      final needed = oneLineOfLabelHeight(tester, locked.first) - 1;
      for (var index = 0; index < locked.evaluate().length; index++) {
        expect(
          tester.getSize(locked.at(index)).height,
          greaterThanOrEqualTo(needed),
        );
      }
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('redeeming still spends exactly the points it advertises',
      (tester) async {
    await pumpLoyaltyScreen(tester);

    expect(find.text('120'), findsOneWidget);

    await tester.tap(find.text('Redeem'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 120 points minus the 100-point cold drink leaves 20.
    expect(find.text('20'), findsOneWidget);
    expect(find.text('Redeem'), findsNothing);
  });

  testWidgets('the pill is tall enough that nothing gets clipped',
      (tester) async {
    await pumpLoyaltyScreen(tester);

    final pill = tester.getRect(
      find.widgetWithText(ElevatedButton, 'Redeem'),
    );
    final label = tester.getRect(find.text('Redeem'));

    expect(pill.height, greaterThanOrEqualTo(40));
    expect(label.top, greaterThanOrEqualTo(pill.top));
    expect(label.bottom, lessThanOrEqualTo(pill.bottom));
  });
}
