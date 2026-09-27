import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/app_theme.dart';
import 'package:mrpizza/core/theme/widgets.dart';
import 'package:mrpizza/features/orders/screens/order_tracking_screen.dart';

/// The rider card's rating and role line was a plain child of a Row, and a Row
/// lays non-flex children out with unbounded width. On a 360dp phone the line
/// needed 152dp inside a 122dp slot and ran 30dp past it, which is the 'RIGHT
/// OVERFLOWED BY 30 PIXELS' stripe that landed under the call button.
void main() {
  const riderRoleLine = '4.95  |  Mr. Pizza Senior Rider';

  Future<void> pumpTrackingScreen(
    WidgetTester tester, {
    Size surface = const Size(360, 800),
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const OrderTrackingScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('the rider card fits the phone it is drawn on', () {
    testWidgets('nothing overflows on a 360dp phone', (tester) async {
      await pumpTrackingScreen(tester);

      // A RenderFlex overflow is reported as a framework error, so this
      // assertion is the 'RIGHT OVERFLOWED BY 30 PIXELS' stripe in a test.
      expect(tester.takeException(), isNull);
    });

    testWidgets('the rating line stays inside the card it belongs to',
        (tester) async {
      await pumpTrackingScreen(tester);

      final riderCard =
          tester.getRect(find.widgetWithText(MrCard, 'Marco Rossi'));
      final roleLine = tester.getRect(find.text(riderRoleLine));

      expect(roleLine.right, lessThanOrEqualTo(riderCard.right));
    });

    testWidgets('the status card survives an even narrower phone',
        (tester) async {
      await pumpTrackingScreen(tester, surface: const Size(320, 800));

      expect(tester.takeException(), isNull);
    });
  });
}
