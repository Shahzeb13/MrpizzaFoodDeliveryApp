import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/app_colors.dart';
import 'package:mrpizza/core/theme/app_theme.dart';
import 'package:mrpizza/features/orders/models/order_tracking.dart';
import 'package:mrpizza/features/orders/presentation/live_order_bar.dart';
import 'package:mrpizza/features/orders/presentation/live_order_visibility.dart';
import 'package:mrpizza/features/orders/providers/live_order_provider.dart';

/// Before this existed, the only place a customer could see that their order
/// had been cancelled was the tracking screen — four taps away through My
/// Orders, by tapping the right row. These tests are about the bar that removed
/// that, and specifically about the promises it makes: it appears without being
/// asked for, it tells the truth about a cancellation, and it never gets in the
/// way of the cart.
void main() {
  const orderId = '11111111-1111-1111-1111-111111111111';

  OrderTracking orderWithStatus(
    String status, {
    String? riderAssignmentStatus,
    String? riderName,
  }) {
    return OrderTracking(
      orderId: orderId,
      billNumber: 'MP-ABT-00042',
      status: status,
      orderType: 'delivery',
      subtotal: 2450,
      tax: 196,
      deliveryCharges: 150,
      discountAmount: 300,
      total: 2496,
      createdAt: DateTime(2026, 9, 29, 14, 15),
      deliveryAddress: 'House 12, Street 4, Mandian, Abbottabad',
      branchName: 'Mr. Pizza - Abbottabad',
      items: const [],
      rider: riderAssignmentStatus == null
          ? null
          : TrackedRider(
              assignmentStatus: riderAssignmentStatus,
              fullName: riderName,
              phone: '+92 331 6290108',
              assignedAt: DateTime(2026, 9, 29, 14, 20),
              pickedUpAt: DateTime(2026, 9, 29, 14, 40),
              deliveredAt: null,
              failureReason: null,
            ),
      timeline: const [],
    );
  }

  Future<ProviderContainer> pumpLiveOrderBar(
    WidgetTester tester, {
    required String status,
    Map<String, LiveOrderConclusion> conclusions = const {},
    Size surface = const Size(360, 800),
    VoidCallback? onOpen,
    String? riderAssignmentStatus,
    String? riderName,
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        liveOrderTrackingProvider.overrideWith(
          (ref) => Stream<OrderTracking?>.value(
            orderWithStatus(
              status,
              riderAssignmentStatus: riderAssignmentStatus,
              riderName: riderName,
            ),
          ),
        ),
        liveOrderConclusionsProvider.overrideWith((ref) => conclusions),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: LiveOrderBar(onOpen: onOpen),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    return container;
  }

  group('the bar shows up without being asked for', () {
    testWidgets('shows the real stage while the order is moving',
        (tester) async {
      await pumpLiveOrderBar(tester, status: 'in_kitchen');

      expect(find.text('Preparing Your Food'), findsOneWidget);
      expect(find.text('The kitchen is cooking your order now'), findsOneWidget);
    });

    testWidgets('shows the bill number the database allocated', (tester) async {
      await pumpLiveOrderBar(tester, status: 'ready_for_pickup');

      expect(find.text('#MP-ABT-00042'), findsOneWidget);
    });

    testWidgets('tells a waiting rider apart from one carrying the food',
        (tester) async {
      // Same stored status, two genuinely different situations for the customer,
      // so the bar has to agree with the tracking screen about which is which.
      await pumpLiveOrderBar(
        tester,
        status: 'out_for_delivery',
        riderAssignmentStatus: 'assigned',
        riderName: 'Bilal',
      );
      expect(find.text('Rider On The Way'), findsOneWidget);
      expect(
        find.text('Bilal is on the way to collect your order'),
        findsOneWidget,
      );

      await pumpLiveOrderBar(
        tester,
        status: 'out_for_delivery',
        riderAssignmentStatus: 'picked_up',
        riderName: 'Bilal',
      );
      expect(find.text('Out For Delivery!'), findsOneWidget);
      expect(find.text('Bilal is bringing your order to you'), findsOneWidget);
    });

    testWidgets('never invents a rider name the branch did not assign',
        (tester) async {
      // No rider yet means "Your rider", not a plausible guess.
      await pumpLiveOrderBar(tester, status: 'ready_for_pickup');

      expect(
        find.text('Your food is packed and waiting for the rider'),
        findsOneWidget,
      );
    });
  });

  group('a cancellation is never dressed up as good news', () {
    testWidgets('says the order was cancelled in plain words', (tester) async {
      await pumpLiveOrderBar(tester, status: 'cancelled');

      expect(find.text('Order Cancelled'), findsOneWidget);
      expect(find.textContaining('was cancelled'), findsOneWidget);
    });

    testWidgets('offers a Dismiss, because it will not time out',
        (tester) async {
      await pumpLiveOrderBar(tester, status: 'cancelled');

      expect(find.text('Dismiss'), findsOneWidget);
    });

    testWidgets('a delivered order can be dismissed early', (tester) async {
      // This used to assert the opposite, on the reasoning that delivery "leaves
      // by itself" so a Dismiss button would be a lie. But it does not leave by
      // itself — it leaves when a 60 second timer the customer cannot see runs
      // out. Offering no way to clear it meant a customer who simply wanted the
      // screen back had to wait. Both endings now offer a button and a swipe;
      // only the deadlines differ.
      await pumpLiveOrderBar(tester, status: 'delivered');

      expect(find.text('Delivered!'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
    });

    testWidgets('paints the cancellation in the danger colour', (tester) async {
      await pumpLiveOrderBar(tester, status: 'cancelled');

      // The regression this guards: the bar was hardcoded to success green, so
      // "Order Cancelled" arrived in the app's good-news colour.
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).borderRadius ==
                  BorderRadius.circular(22) &&
              ((widget.decoration! as BoxDecoration).border?.top.color ==
                      AppColors.danger.withValues(alpha: 0.32) ||
                  (widget.decoration! as BoxDecoration).color ==
                      AppColors.danger),
        ),
        findsWidgets,
      );
    });
  });

  group('the bar keeps out of the way', () {
    testWidgets('shows nothing at all when the customer has no order',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          liveOrderTrackingProvider.overrideWith(
            (ref) => Stream<OrderTracking?>.value(null),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: LiveOrderBar()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Preparing Your Food'), findsNothing);
    });

    testWidgets('stays silent while the first read is still in flight',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer(
        overrides: [
          liveOrderTrackingProvider.overrideWith(
            (ref) => const Stream<OrderTracking?>.empty(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: LiveOrderBar()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  group('it remembers what has already been shown', () {
    testWidgets('a dismissed cancellation does not come back',
        (tester) async {
      final container = await pumpLiveOrderBar(
        tester,
        status: 'cancelled',
        conclusions: {
          orderId: LiveOrderConclusion(
            firstShownTerminalAt: DateTime(2026, 9, 29, 12),
            dismissedAt: DateTime(2026, 9, 29, 12, 5),
          ),
        },
      );

      expect(find.text('Order Cancelled'), findsNothing);
      expect(container.read(liveOrderConclusionsProvider), hasLength(1));
    });

    testWidgets('a cancellation dismissed minutes ago stays dismissed',
        (tester) async {
      await pumpLiveOrderBar(
        tester,
        status: 'cancelled',
        conclusions: {
          orderId: LiveOrderConclusion(
            firstShownTerminalAt: DateTime(2026, 9, 29, 12),
            dismissedAt: DateTime(2026, 9, 29, 12, 1),
          ),
        },
      );

      expect(find.text('Dismiss'), findsNothing);
      expect(find.text('Order Cancelled'), findsNothing);
    });

    testWidgets('tapping Dismiss records the acknowledgement',
        (tester) async {
      final container = await pumpLiveOrderBar(tester, status: 'cancelled');

      await tester.tap(find.text('Dismiss'));
      await tester.pump(const Duration(milliseconds: 700));

      final conclusion =
          container.read(liveOrderConclusionsProvider)[orderId];
      expect(conclusion, isNotNull);
      expect(conclusion!.dismissedAt, isNotNull);
      expect(find.text('Order Cancelled'), findsNothing);
    });

    testWidgets('an undismissed cancellation is recorded as shown',
        (tester) async {
      // The "first seen at" timestamp is what the delivery auto-hide counts
      // from, so a bar that showed a result without recording it would leave a
      // delivered order stuck on screen forever.
      final container = await pumpLiveOrderBar(tester, status: 'delivered');

      final conclusion = container.read(liveOrderConclusionsProvider)[orderId];
      expect(conclusion, isNotNull);
      expect(conclusion!.firstShownTerminalAt, isNotNull);
      expect(conclusion.isDismissed, isFalse);
    });
  });

  group('swiping clears an ending', () {
    testWidgets('a delivered order can be swiped away', (tester) async {
      // The delivered bar used to have no way out of it except waiting out the
      // confirmation window — a timer the customer cannot see and does not
      // control. Acknowledging it should be one gesture, not patience.
      final container = await pumpLiveOrderBar(tester, status: 'delivered');

      expect(find.text('Delivered!'), findsOneWidget);
      expect(find.byType(Dismissible), findsOneWidget);

      await tester.drag(find.text('Delivered!'), const Offset(600, 0));
      await tester.pumpAndSettle();

      final conclusion = container.read(liveOrderConclusionsProvider)[orderId];
      expect(conclusion, isNotNull);
      expect(conclusion!.isDismissed, isTrue);
      expect(find.text('Delivered!'), findsNothing);
    });

    testWidgets('a cancelled order can be swiped away', (tester) async {
      final container = await pumpLiveOrderBar(tester, status: 'cancelled');

      await tester.drag(find.text('Order Cancelled'), const Offset(600, 0));
      await tester.pumpAndSettle();

      final conclusion = container.read(liveOrderConclusionsProvider)[orderId];
      expect(conclusion!.isDismissed, isTrue);
      expect(find.text('Order Cancelled'), findsNothing);
    });

    testWidgets('an order that is still moving cannot be swiped away',
        (tester) async {
      // The one guarantee this bar makes is that an order in flight is visible.
      // A gesture that could dismiss that would defeat the entire feature, so
      // the active stages carry no Dismissible at all.
      final container = await pumpLiveOrderBar(tester, status: 'in_kitchen');

      expect(find.byType(Dismissible), findsNothing);

      await tester.drag(find.text('Preparing Your Food'), const Offset(600, 0));
      // Bounded pumps, not pumpAndSettle: the active badge breathes forever by
      // design, so the tree can never go quiet while an order is in flight.
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      expect(find.text('Preparing Your Food'), findsOneWidget);
      final conclusion = container.read(liveOrderConclusionsProvider)[orderId];
      expect(conclusion, isNull);
    });
  });

  group('tapping the bar goes to the order it is showing', () {
    testWidgets('pins the order before opening tracking', (tester) async {
      // Without pinning, the tracking screen resolves "newest order not yet
      // finished" and would land on a different order than the one the customer
      // tapped — which is exactly the bug on a cancelled order.
      var openTapped = false;
      final container = ProviderContainer(
        overrides: [
          liveOrderIdProvider.overrideWith((ref) async => orderId),
          liveOrderTrackingProvider.overrideWith(
            (ref) => Stream<OrderTracking?>.value(orderWithStatus('cancelled')),
          ),
          liveOrderConclusionsProvider.overrideWith((ref) => const {}),
        ],
      );
      addTearDown(container.dispose);

      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: LiveOrderBar(
                onOpen: () => openTapped = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      await tester.tap(find.text('Order Cancelled'));
      await tester.pump(const Duration(milliseconds: 700));

      expect(openTapped, isTrue);
    });
  });
}
