import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/app_theme.dart';
import 'package:mrpizza/features/orders/models/order_tracking.dart';
import 'package:mrpizza/features/orders/presentation/live_order_bar.dart';
import 'package:mrpizza/features/orders/presentation/order_status_copy.dart';
import 'package:mrpizza/features/orders/providers/live_order_provider.dart';

/// A pickup order has no rider and no address. The moment the app says otherwise
/// it is lying to somebody standing at a counter, waiting for food that is
/// already there.
///
/// These tests exist because `order_type` was stored for months and read by
/// nothing. The customer was told their pickup order was "packed and waiting for
/// the rider" and then shown a five-step progress track whose middle two steps
/// were "On The Way" and "Delivered".
OrderTracking pickupOrder({required String status}) {
  return OrderTracking(
    orderId: '33333333-3333-3333-3333-333333333333',
    billNumber: 'ABT-090',
    status: status,
    orderType: 'pickup',
    subtotal: 1500,
    tax: 120,
    deliveryCharges: 0,
    discountAmount: 0,
    total: 1620,
    createdAt: DateTime.now(),
    deliveryAddress: '',
    branchName: 'Mr. Pizza - Mansehra',
    items: const [],
    // Deliberately absent. A pickup order has no rider and none can be assigned.
    rider: null,
    timeline: const [],
  );
}

OrderTracking deliveryOrder({required String status}) {
  return OrderTracking(
    orderId: '44444444-4444-4444-4444-444444444444',
    billNumber: 'ABT-091',
    status: status,
    orderType: 'delivery',
    subtotal: 1500,
    tax: 120,
    deliveryCharges: 150,
    discountAmount: 0,
    total: 1770,
    createdAt: DateTime.now(),
    deliveryAddress: 'House 12, Mandian, Abbottabad',
    branchName: 'Mr. Pizza - Abbottabad',
    items: const [],
    rider: const TrackedRider(
      assignmentStatus: 'assigned',
      fullName: 'Bilal',
      phone: '+92 331 6290108',
      assignedAt: null,
      pickedUpAt: null,
      deliveredAt: null,
      failureReason: null,
    ),
    timeline: const [],
  );
}

void main() {
  group('a pickup order is never told a rider is involved', () {
    test('bagged and waiting names the branch, not a rider', () {
      final order = pickupOrder(status: 'ready_for_pickup');

      expect(stageHeadline(order.stage, order), 'Ready to Collect!');
      expect(
        stageSubtitle(order.stage, order),
        'Your food is packed and waiting at Mr. Pizza - Mansehra',
      );
    });

    test('finished means collected, not delivered', () {
      // Nobody delivered anything. The customer walked out of the shop with it,
      // and "Delivered!" on that screen is them being told to wait for someone
      // who is never coming.
      final order = pickupOrder(status: 'delivered');

      expect(stageHeadline(order.stage, order), 'Collected!');
      expect(stageSubtitle(order.stage, order), 'You have collected your order. Enjoy!');
    });

    test('no stage mentions a rider', () {
      for (final status in [
        'confirmed',
        'in_kitchen',
        'ready_for_pickup',
        'delivered',
        'cancelled',
      ]) {
        final order = pickupOrder(status: status);
        final said = '${stageHeadline(order.stage, order)} '
            '${stageSubtitle(order.stage, order)}';
        expect(
          said.toLowerCase(),
          isNot(contains('rider')),
          reason: '"$status" told the customer about a rider on a pickup order',
        );
      }
    });

    test('a pickup order pushed into a rider stage admits the app is wrong', () {
      // The database now refuses this transition. But a row edited before the
      // guard existed, or written by something with raw table access, can still
      // look like this — and inventing a rider for it is the one thing that
      // must not happen.
      final order = pickupOrder(status: 'out_for_delivery');

      expect(stageHeadline(order.stage, order), 'Status Unavailable');
      expect(
        stageSubtitle(order.stage, order),
        contains('marked as a delivery by mistake'),
      );
    });
  });

  group('a delivery order is untouched', () {
    test('still says the food is waiting for the rider', () {
      final order = deliveryOrder(status: 'ready_for_pickup');

      expect(stageHeadline(order.stage, order), 'Ready for Pickup');
      expect(
        stageSubtitle(order.stage, order),
        'Your food is packed and waiting for the rider',
      );
    });

    test('still finishes with Delivered', () {
      final order = deliveryOrder(status: 'delivered');

      expect(stageHeadline(order.stage, order), 'Delivered!');
      expect(stageSubtitle(order.stage, order), 'Your order has been delivered');
    });
  });

  group('the progress track is sized by the order, not by the screen', () {
    test('a pickup order has three steps', () {
      expect(
        pickupOrder(status: 'confirmed').pipelineLength,
        OrderTracking.pickupPipelineStepCount,
      );
      expect(OrderTracking.pickupPipelineStepCount, 3);
    });

    test('a delivery order still has five', () {
      expect(
        deliveryOrder(status: 'confirmed').pipelineLength,
        OrderTracking.pipelineStepCount,
      );
      expect(OrderTracking.pipelineStepCount, 5);
    });

    test('a collected pickup order fills its whole track', () {
      // The bug this guards: progress was computed against a hard-coded five
      // steps, so a three-step track topped out at three-fifths — a customer
      // holding their finished order looking at a bar that had not even
      // finished filling.
      final order = pickupOrder(status: 'delivered');
      final reached = pipelineProgressFor(
        order.stage,
        stepCount: order.pipelineLength,
      );

      expect(reached / order.pipelineLength, 1.0);
    });

    test('a delivered delivery order still fills its track', () {
      final order = deliveryOrder(status: 'delivered');

      expect(
        pipelineProgressFor(order.stage, stepCount: order.pipelineLength) /
            order.pipelineLength,
        1.0,
      );
    });

    test('a rider stage cannot overrun a three-step track', () {
      final reached = pipelineProgressFor(
        OrderStage.outForDelivery,
        stepCount: OrderTracking.pickupPipelineStepCount,
      );

      expect(reached, lessThanOrEqualTo(OrderTracking.pickupPipelineStepCount));
    });
  });

  group('the live bar reads a pickup order as a pickup order', () {
    Future<void> pumpBar(WidgetTester tester, OrderTracking order) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer(
        overrides: [
          liveOrderTrackingProvider.overrideWith(
            (ref) => Stream<OrderTracking?>.value(order),
          ),
          liveOrderConclusionsProvider.overrideWith((ref) => const {}),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: Align(
              alignment: Alignment.bottomCenter,
              child: LiveOrderBar(),
            )),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
    }

    testWidgets('says Collected! and never mentions a rider', (tester) async {
      await pumpBar(tester, pickupOrder(status: 'delivered'));

      expect(find.text('Collected!'), findsOneWidget);
      expect(find.textContaining('rider', findRichText: true), findsNothing);
    });

    testWidgets('names the branch when the food is ready', (tester) async {
      await pumpBar(tester, pickupOrder(status: 'ready_for_pickup'));

      expect(find.text('Ready to Collect!'), findsOneWidget);
      expect(
        find.text('Your food is packed and waiting at Mr. Pizza - Mansehra'),
        findsOneWidget,
      );
    });

    testWidgets('shows no dismiss row, because nothing is still moving', (
      tester,
    ) async {
      // Same as any other in-flight order: the bar makes one guarantee, and it
      // is that you can see an order that has not finished.
      await pumpBar(tester, pickupOrder(status: 'ready_for_pickup'));

      expect(find.text('Dismiss'), findsNothing);
      expect(find.byType(Dismissible), findsNothing);
    });
  });
}