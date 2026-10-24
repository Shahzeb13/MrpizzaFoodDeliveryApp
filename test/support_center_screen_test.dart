import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mrpizza/features/profile/models/support_document.dart';
import 'package:mrpizza/features/profile/screens/support_center_screen.dart';

/// Mirrors the app's routes closely enough to prove the row opens the right
/// document. The real document screen is a WebView and cannot be built in a
/// widget test, so it is replaced with a label carrying the route parameter.
GoRouter _router(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/support',
        builder: (context, state) => const SupportCenterScreen(),
        routes: [
          GoRoute(
            path: 'document/:document',
            builder: (context, state) => Scaffold(
              body: Text('opened:${state.pathParameters['document']}'),
            ),
          ),
        ],
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, {String at = '/support'}) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: _router(at)));
  await tester.pumpAndSettle();
}

void main() {
  group('the Support Center lists every published document', () {
    testWidgets('shows all five policies and FAQs', (tester) async {
      await _pump(tester);

      for (final document in SupportDocument.values) {
        expect(find.text(document.label), findsOneWidget,
            reason: '${document.label} is missing from the Support Center');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('still offers a way to contact the shop', (tester) async {
      await _pump(tester);

      expect(find.text('Call Us'), findsOneWidget);
      expect(find.text('WhatsApp Chat'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the inline FAQ answers are gone, not duplicated', (tester) async {
      // The questions used to be hardcoded here with figures that no longer
      // matched the branch settings. They now come from the website, so nothing
      // may be restated on this screen.
      await _pump(tester);

      expect(find.text('How long does pizza delivery take?'), findsNothing);
      expect(find.byType(ExpansionTile), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('opening a document', () {
    // One test per document, so a whole fresh tree is built each time. Reusing
    // one router across taps would keep whatever page the previous tap opened.
    for (final document in SupportDocument.values) {
      testWidgets('the ${document.label} row opens its own page',
          (tester) async {
        await _pump(tester);

        // The list scrolls on a short screen, so the last row can start below
        // the fold. Bring it into view the way a customer would.
        await tester.ensureVisible(find.text(document.label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(document.label));
        await tester.pumpAndSettle();

        expect(find.text('opened:${document.slug}'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
