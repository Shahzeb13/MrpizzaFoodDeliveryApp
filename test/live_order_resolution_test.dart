import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/app_theme.dart';
import 'package:mrpizza/features/orders/data/order_tracking_repository.dart';
import 'package:mrpizza/features/orders/models/order_tracking.dart';
import 'package:mrpizza/features/orders/presentation/live_order_bar.dart';
import 'package:mrpizza/features/orders/providers/live_order_provider.dart';
import 'package:mrpizza/features/orders/providers/order_tracking_provider.dart';

/// Reproduces the REAL resolution chain the bar uses on a browse screen, with
/// nothing stubbed except the database itself.
///
/// The first bar tests overrode `liveOrderTrackingProvider` outright, which
/// skipped `liveOrderIdProvider` and `myOrdersProvider` entirely. That let a bug
/// in the chain through: the lookup is a caching provider, so it decided once
/// per app session what the bar shows and never asked again.
class _FakeOrderRepository extends OrderTrackingRepository {
  _FakeOrderRepository({required this.orders, required this.tracking});

  List<OrderSummary> orders;
  OrderTracking? tracking;

  /// Channel names the bar subscribed with, so a collision with the tracking
  /// screen's channel is caught here instead of showing up as a bar that goes
  /// randomly stale.
  final List<String> watchedPrefixes = [];

  @override
  Future<List<OrderSummary>> fetchMyOrders() async => orders;

  /// Overridden rather than [fetchMyOrders] because `myOrdersProvider` is a
  /// stream now — the list subscribes instead of taking one snapshot. Tests
  /// drive updates by reassigning [orders] and invalidating the provider.
  @override
  Stream<List<OrderSummary>> watchMyOrders() => Stream.value(orders);

  @override
  Stream<OrderTracking?> watchOrderTracking(
    String orderId, {
    String channelPrefix = 'order-tracking',
  }) {
    watchedPrefixes.add(channelPrefix);
    final current = tracking;
    return current == null
        ? Stream<OrderTracking?>.value(null)
        : Stream<OrderTracking?>.value(current);
  }
}

/// The exact order the user placed while testing, as the database holds it.
///
/// [createdAt] defaults to now so fixtures stay adoptable. The adoption rules
/// reject anything older than an hour — deliberately, because that is what a
/// stuck development row looks like — so a hardcoded date would quietly stop
/// exercising the bar at all.
OrderTracking buildRealOrderABT020({DateTime? createdAt}) {
  return OrderTracking(
    orderId: '62243bf7-1e81-4e7c-9458-66be0e95606e',
    billNumber: 'ABT-020',
    status: 'ready_for_pickup',
    orderType: 'delivery',
    subtotal: 2377.65,
    tax: 190.21,
    deliveryCharges: 150,
    discountAmount: 357,
    total: 2360.86,
    createdAt: createdAt ?? DateTime.now(),
    deliveryAddress: 'Triple one hotel near comsats',
    branchName: 'Mr. Pizza - Abbottabad',
    items: const [],
    rider: null,
    timeline: const [],
  );
}

OrderSummary buildFinishedSummary(String orderId) {
  return OrderSummary(
    orderId: orderId,
    billNumber: 'MP-ABT-00019',
    status: 'delivered',
    orderType: 'delivery',
    subtotal: 2450,
    tax: 196,
    deliveryCharges: 150,
    discountAmount: 0,
    total: 2796,
    createdAt: DateTime.utc(2026, 9, 28, 19, 2),
    branchName: 'Mr. Pizza - Abbottabad',
    itemSummary: '1x Chicken Tikka Supreme',
    itemCount: 1,
    riderName: null,
  );
}

OrderSummary buildInFlightSummary(OrderTracking tracking) {
  return OrderSummary(
    orderId: tracking.orderId,
    billNumber: tracking.billNumber,
    status: tracking.status,
    orderType: tracking.orderType,
    subtotal: tracking.subtotal,
    tax: tracking.tax,
    deliveryCharges: tracking.deliveryCharges,
    discountAmount: tracking.discountAmount,
    total: tracking.total,
    createdAt: tracking.createdAt,
    branchName: tracking.branchName,
    itemSummary: '2x Chicken Tikka Supreme',
    itemCount: 2,
    riderName: 'alyan',
  );
}

/// Builds the same order with a few fields changed.
///
/// Dart has no object spread, and copying the whole constructor by hand at each
/// call site is how a test ends up quietly testing a different order than the
/// one it names.
OrderTracking copyOrder(
  OrderTracking base, {
  String? orderId,
  String? billNumber,
  String? status,
  DateTime? createdAt,
}) {
  return OrderTracking(
    orderId: orderId ?? base.orderId,
    billNumber: billNumber ?? base.billNumber,
    status: status ?? base.status,
    orderType: base.orderType,
    subtotal: base.subtotal,
    tax: base.tax,
    deliveryCharges: base.deliveryCharges,
    discountAmount: base.discountAmount,
    total: base.total,
    createdAt: createdAt ?? base.createdAt,
    deliveryAddress: base.deliveryAddress,
    branchName: base.branchName,
    items: base.items,
    rider: base.rider,
    timeline: base.timeline,
  );
}

void main() {
/// Pumps the real bar over the real provider chain. Returns the container so
  /// tests can inspect the pin and force a re-lookup the way app resume does.
  Future<ProviderContainer> pumpBars(
    WidgetTester tester,
    _FakeOrderRepository repository,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        orderTrackingRepositoryProvider.overrideWithValue(repository),
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
              child: LiveOrderBottomBars(onCheckout: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    // Adoption writes the pin in a microtask, which re-runs the lookup and
    // restarts the tracking stream behind it. Settle that chain before any
    // assertion, or a test measures how many frames Riverpod happened to need
    // rather than what the bar decided.
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    return container;
  }

  testWidgets(
    'the bar resolves the live order through the real provider chain',
    (tester) async {
      final order = buildRealOrderABT020();
      await pumpBars(
        tester,
        _FakeOrderRepository(
          orders: [buildInFlightSummary(order)],
          tracking: order,
        ),
      );

      expect(find.text('Ready for Pickup'), findsOneWidget);
      expect(find.text('#ABT-020'), findsOneWidget);
      expect(
        find.text('Your food is packed and waiting for the rider'),
        findsOneWidget,
      );
    },
  );

  testWidgets('the bar uses its own realtime channel name', (tester) async {
    final order = buildRealOrderABT020();
    final repository = _FakeOrderRepository(
      orders: [buildInFlightSummary(order)],
      tracking: order,
    );
    await pumpBars(tester, repository);

    expect(repository.watchedPrefixes, isNotEmpty);
    expect(repository.watchedPrefixes, everyElement('live-order'));
  });

  testWidgets(
    'a customer who only has old orders sees no bar',
    (tester) async {
      await pumpBars(
        tester,
        _FakeOrderRepository(
          orders: [buildFinishedSummary('11111111-1111-1111-1111-111111111111')],
          tracking: null,
        ),
      );

      expect(find.text('Ready for Pickup'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'an order placed after the app was already open still shows up',
    (tester) async {
      // This is the bug that hid the bar on a real device. The app was launched
      // with nothing in flight, the lookup cached "no active order", and placing
      // a real order afterwards never invalidated it — so the bar stayed hidden
      // for the rest of the session even though a live order existed. Force
      // stopping the app "fixed" it, which is what made it look like a stale
      // build rather than a logic fault.
      final repository = _FakeOrderRepository(
        orders: [buildFinishedSummary('11111111-1111-1111-1111-111111111111')],
        tracking: null,
      );
      await pumpBars(tester, repository);

      expect(find.text('Ready for Pickup'), findsNothing);

      // The customer places a real order, then comes back to the app.
      final order = buildRealOrderABT020();
      repository.orders = [buildInFlightSummary(order)];
      repository.tracking = order;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      await pumpUntilFound(tester, find.text('Ready for Pickup'));

      expect(find.text('Ready for Pickup'), findsOneWidget);
      expect(find.text('#ABT-020'), findsOneWidget);
    },
  );

  // -----------------------------------------------------------------------
  // The bug this whole rewrite is about: once an order finished, the bar used
  // to re-run "newest unfinished order" and pick up a previous one, popping
  // back up with no event to explain it.
  // -----------------------------------------------------------------------

  group('adoption refuses orders that cannot be trusted', () {
    testWidgets(
      'a stuck order from a previous session is never adopted',
      (tester) async {
        // The development-data shape: status still says `ready_for_pickup`, but
        // it was placed hours ago and nobody ever moved it. It looks exactly
        // like a live order to a status check alone.
        final order = buildRealOrderABT020(
          createdAt: DateTime.now().subtract(const Duration(hours: 3)),
        );
        await pumpBars(
          tester,
          _FakeOrderRepository(
            orders: [buildInFlightSummary(order)],
            tracking: order,
          ),
        );

        expect(find.text('Ready for Pickup'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
      },
    );

    testWidgets('an order just inside the age limit is still adopted', (
      tester,
    ) async {
      // The guard is a ceiling, not a blanket rejection of anything not brand
      // new. An order placed 40 minutes ago is exactly what a slow-but-real
      // delivery looks like.
      final order = buildRealOrderABT020(
        createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
      );
      await pumpBars(
        tester,
        _FakeOrderRepository(
          orders: [buildInFlightSummary(order)],
          tracking: order,
        ),
      );

      expect(find.text('Ready for Pickup'), findsOneWidget);
    });

    testWidgets('a status the app cannot read is never adopted', (
      tester,
    ) async {
      // Fresh, in-flight looking, and unreadable. Failing open here would put
      // it on the bar claiming to have only just been placed.
      final order = copyOrder(
        buildRealOrderABT020(),
        status: 'awaiting_rider_approval',
      );
      await pumpBars(
        tester,
        _FakeOrderRepository(
          orders: [buildInFlightSummary(order)],
          tracking: order,
        ),
      );

      expect(find.text('Order Placed!'), findsNothing);
      expect(find.text('Status Unavailable'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  group('the bar commits to one order', () {
    testWidgets(
      'a newer order appearing does not steal the bar mid-flight',
      (tester) async {
        final followed = buildRealOrderABT020();
        final repository = _FakeOrderRepository(
          orders: [buildInFlightSummary(followed)],
          tracking: followed,
        );
        final container = await pumpBars(tester, repository);
        expect(find.text('#ABT-020'), findsOneWidget);

        // A newer order turns up — another device, or a re-placed order. The
        // bar is following a specific order and must stay on it; the lookup
        // cannot run again and hand the customer a different pizza.
        final newer = copyOrder(
          followed,
          orderId: '99999999-9999-9999-9999-999999999999',
          billNumber: 'ABT-021',
          createdAt: DateTime.now(),
        );
        repository.orders = [
          buildInFlightSummary(newer),
          buildInFlightSummary(followed),
        ];
        container.invalidate(myOrdersProvider);
        container.invalidate(liveOrderIdProvider);
        await pumpUntilFound(tester, find.text('#ABT-020'));

        // Same order, still. The re-lookup ran and had a newer, perfectly
        // adoptable order sitting right there to pick up instead.
        expect(find.text('#ABT-021'), findsNothing);
        expect(container.read(pinnedLiveOrderIdProvider), followed.orderId);
      },
    );

    testWidgets(
      'a finished order is retired and a genuinely new one is adopted',
      (tester) async {
        final first = buildRealOrderABT020();
        final repository = _FakeOrderRepository(
          orders: [buildInFlightSummary(first)],
          tracking: first,
        );
        final container = await pumpBars(tester, repository);
        expect(container.read(pinnedLiveOrderIdProvider), first.orderId);

        // It gets delivered. The bar shows the confirmation, then retires it —
        // which must release the pin, or the bar is stuck on a finished order
        // forever. The fake stream only reads at subscribe time, so the
        // re-subscribe is what makes the status change observable.
        final delivered = copyOrder(first, status: 'delivered');
        repository.tracking = delivered;
        container.invalidate(liveOrderTrackingProvider);
        await pumpUntilFound(tester, find.text('Delivered!'));

        // The confirmation window, then it retires itself. Pumped a second at a
        // time rather than jumping the clock in one go, because the timer
        // callback writes a provider and the resulting rebuild needs a real
        // frame to land — the bug being guarded here is about that whole path
        // releasing nothing.
        for (var second = 0; second < 70; second++) {
          await tester.pump(const Duration(seconds: 1));
        }

        expect(find.text('Delivered!'), findsNothing);
        expect(container.read(pinnedLiveOrderIdProvider), isNull);

        // Retirement does two things, and both matter. Releasing the pin stops
        // the bar being stuck on a finished order; CLOSING adoption stops the
        // next lookup from helping itself to some other unfinished order. A
        // re-opened adoption test lives alongside this one — re-opening is the
        // customer's decision to place an order, never the bar's own idea.
        expect(container.read(liveOrderAdoptionClosedProvider), isTrue);
      },
    );

    testWidgets(
      'a finished order is not replaced by an older one still in flight',
      (tester) async {
        // The customer ordered twice. The newer one completed first. The older
        // one is genuinely unfinished and recent, so every rule that exists to
        // pick an order would happily select it — and the bar would pop back up
        // showing the previous order with nothing having prompted it.
        //
        // The bar follows one order per session unless the customer places a
        // new one. "Nothing to show" is the honest answer here.
        final older = buildRealOrderABT020();
        final newer = copyOrder(
          older,
          orderId: '77777777-7777-7777-7777-777777777777',
          billNumber: 'ABT-023',
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        );

        final repository = _FakeOrderRepository(
          orders: [buildInFlightSummary(newer)],
          tracking: newer,
        );
        final container = await pumpBars(tester, repository);
        expect(container.read(pinnedLiveOrderIdProvider), newer.orderId);

        // The newer order is delivered and the bar retires it.
        final delivered = copyOrder(newer, status: 'delivered');
        repository.tracking = delivered;
        container.invalidate(liveOrderTrackingProvider);
        await pumpUntilFound(tester, find.text('Delivered!'));
        for (var second = 0; second < 70; second++) {
          await tester.pump(const Duration(seconds: 1));
        }
        expect(container.read(pinnedLiveOrderIdProvider), isNull);

        // The older order is still sitting there, unfinished and inside the age
        // limit. It must stay untouched.
        repository.orders = [
          buildInFlightSummary(delivered),
          buildInFlightSummary(older),
        ];
        repository.tracking = older;
        container.invalidate(myOrdersProvider);
        container.invalidate(liveOrderIdProvider);
        container.invalidate(liveOrderTrackingProvider);
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(container.read(pinnedLiveOrderIdProvider), isNull);
        expect(find.text('#ABT-020'), findsNothing);
        expect(find.text('Ready for Pickup'), findsNothing);
      },
    );

    testWidgets('placing a new order re-opens adoption', (tester) async {
      // The escape hatch that makes the rule above safe: the customer can always
      // take the bar to a new order, because that is a decision they made.
      final older = buildRealOrderABT020();
      final repository = _FakeOrderRepository(
        orders: [buildInFlightSummary(older)],
        tracking: older,
      );
      final container = await pumpBars(tester, repository);

      // The order concludes.
      final delivered = copyOrder(older, status: 'delivered');
      repository.tracking = delivered;
      container.invalidate(liveOrderTrackingProvider);
      await pumpUntilFound(tester, find.text('Delivered!'));
      for (var second = 0; second < 70; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(
        container.read(liveOrderAdoptionClosedProvider),
        isTrue,
        reason: 'adoption closes once the followed order concludes',
      );

      // Checkout completes for a brand new order.
      final fresh = copyOrder(
        older,
        orderId: '66666666-6666-6666-6666-666666666666',
        billNumber: 'ABT-024',
        createdAt: DateTime.now(),
      );
      repository.orders = [
        buildInFlightSummary(fresh),
        buildInFlightSummary(delivered),
      ];
      repository.tracking = fresh;
      startFollowingNewlyPlacedOrderForTest(container);

      await pumpUntilFound(tester, find.text('#ABT-024'));

      expect(container.read(pinnedLiveOrderIdProvider), fresh.orderId);
    });
  });
}

/// Calls the same reset checkout performs, without needing a [WidgetRef].
///
/// The production call takes a `WidgetRef` because it is invoked from the
/// checkout screen. Reaching for the same two providers by hand keeps the test
/// exercising the real reset rather than a copy of it.
void startFollowingNewlyPlacedOrderForTest(ProviderContainer container) {
  container.read(pinnedLiveOrderIdProvider.notifier).state = null;
  container.read(liveOrderAdoptionClosedProvider.notifier).state = false;
  container.invalidate(myOrdersProvider);
  container.invalidate(liveOrderIdProvider);
}

/// Pumps until [finder] no longer matches, or fails after a bounded number of
/// frames.
Future<void> pumpUntilGone(WidgetTester tester, Finder finder) async {
  for (var frame = 0; frame < 60; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isEmpty) return;
  }
  fail('The live order bar never went away after 60 frames');
}

/// Pumps until [finder] matches, or fails after a bounded number of frames.
///
/// Invalidating the lookup restarts a FutureProvider and then a StreamProvider,
/// so the bar appears a few frames later rather than instantly. Counting fixed
/// pumps made this test pass or fail based on how many microtask turns the
/// provider happened to need that day.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var frame = 0; frame < 40; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('The live order bar never appeared after 40 frames');
}

