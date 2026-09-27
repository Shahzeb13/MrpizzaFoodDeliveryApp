import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/widgets.dart';
import 'package:mrpizza/features/rider/screens/rider_screen.dart';

/// [MrSectionTitle] used to wrap its title in an `Expanded` unconditionally.
/// Flutter hands a non-flex child of a `Row` an unbounded width, so any screen
/// that set a section title beside something else threw
/// "RenderFlex children have non-zero flex but incoming width constraints are
/// unbounded" on every layout pass. That killed the rider dashboard outright.
void main() {
  group('a section title survives a bounded or unbounded width', () {
    testWidgets('renders as a non-flex child beside another widget',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                MrSectionTitle(title: 'Recent Deliveries'),
                Text('Today'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Recent Deliveries'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders on its own in a normal column', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [MrSectionTitle(title: 'Recent Deliveries')],
            ),
          ),
        ),
      );

      expect(find.text('Recent Deliveries'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders with an eyebrow above the title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MrSectionTitle(
              eyebrow: 'Step 1 of 4',
              title: 'Pickup',
            ),
          ),
        ),
      );

      // MrEyebrow renders its label upper-cased.
      expect(find.text('STEP 1 OF 4'), findsOneWidget);
      expect(find.text('Pickup'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('still pins a trailing widget to the far edge',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: MrSectionTitle(title: 'Order Summary'),
                ),
                Text('Rs. 0'),
              ],
            ),
          ),
        ),
      );

      final title = tester.getRect(find.text('Order Summary'));
      final trailing = tester.getRect(find.text('Rs. 0'));
      expect(trailing.left, greaterThan(title.right));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the rider dashboard renders without framework assertions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: RiderScreen()),
      ),
    );
    await tester.pump();
    semantics.dispose();

    expect(find.text('Rider Dashboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
