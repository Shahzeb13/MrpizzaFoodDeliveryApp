import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/app_theme.dart';
import 'package:mrpizza/core/theme/widgets.dart';
import 'package:mrpizza/features/orders/models/order_tracking.dart';
import 'package:mrpizza/features/orders/providers/order_tracking_provider.dart';
import 'package:mrpizza/features/orders/screens/order_tracking_screen.dart';

/// The rider card's name and assignment line were plain children of a Row, and
/// a Row lays non-flex children out with unbounded width. On a 360dp phone the
/// line needed 152dp inside a 122dp slot and ran 30dp past it, which is the
/// 'RIGHT OVERFLOWED BY 30 PIXELS' stripe that landed under the call button.
///
/// That guard still matters — it is now checked against a real rider name and
/// the real assignment wording, because the row is still a Row.
void main() {
  /// A real assignment the database can actually store, with a name long enough
  /// to push the layout the way the old "Marco Rossi" card did.
  const riderName = 'Muhammad Abdul Wahab Khan';
  const assignmentWording = 'Has your order and is on the way to you';

  OrderTracking buildTrackedOrder({
    String status = 'out_for_delivery',
    String? riderAssignmentStatus = 'picked_up',
    String? riderFullName = riderName,
  }) {
    return OrderTracking(
      orderId: '11111111-1111-1111-1111-111111111111',
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
      items: const [
        TrackedOrderItem(
          menuItemId: 'a',
          name: 'Chicken Tikka Supreme',
          imageUrl: null,
          quantity: 1,
          priceAtOrder: 2450,
        ),
      ],
      rider: TrackedRider(
        assignmentStatus: riderAssignmentStatus ?? '',
        fullName: riderFullName,
        phone: '+92 331 6290108',
        assignedAt: DateTime(2026, 9, 29, 14, 20),
        pickedUpAt: DateTime(2026, 9, 29, 14, 40),
        deliveredAt: null,
        failureReason: null,
      ),
      timeline: const [
        TrackedStatusChange(
          status: 'confirmed',
          changedAt: null,
        ),
      ],
    );
  }

  Future<void> pumpTrackingScreen(
    WidgetTester tester, {
    Size surface = const Size(360, 800),
    OrderTracking? tracking,
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [
        trackedOrderIdProvider.overrideWith((_) => 'order-under-test'),
        orderIdToTrackProvider.overrideWith((ref) async => 'order-under-test'),
        activeOrderTrackingProvider.overrideWith(
          (ref) => Stream<OrderTracking?>.value(
            tracking ?? buildTrackedOrder(),
          ),
        ),
      ],
    );
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

    testWidgets('the assignment line stays inside the card it belongs to',
        (tester) async {
      await pumpTrackingScreen(tester);

      final riderCard = tester.getRect(find.widgetWithText(MrCard, riderName));
      final roleLine = tester.getRect(find.text(assignmentWording));

      expect(roleLine.right, lessThanOrEqualTo(riderCard.right));
    });

    testWidgets('the status card survives an even narrower phone',
        (tester) async {
      await pumpTrackingScreen(tester, surface: const Size(320, 800));

      expect(tester.takeException(), isNull);
    });
  });

  group('the screen shows the database, not a simulation', () {
    testWidgets('the headline comes from the stored order status',
        (tester) async {
      await pumpTrackingScreen(tester);

      expect(find.text('Out For Delivery!'), findsOneWidget);
      // The old screen hardcoded this on every order regardless of its status.
      expect(find.text('Baking in Wood-Fired Oven'), findsNothing);
    });

    testWidgets('ready_for_pickup is its own stage, not "being cooked"',
        (tester) async {
      await pumpTrackingScreen(
        tester,
        tracking: buildTrackedOrder(
          status: 'ready_for_pickup',
          riderAssignmentStatus: null,
          riderFullName: null,
        ),
      );

      // The headline is the stage, and it must not read as "being cooked".
      expect(find.text('Ready for Pickup'), findsOneWidget);
      expect(find.text('Preparing Your Food'), findsNothing);
      // It is a status the app knows, so no raw-value escape hatch.
      expect(find.textContaining('Status: '), findsNothing);

      // And it is its own step in the pipeline, sitting between the kitchen and
      // the rider.
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Ready for Pickup'), findsOneWidget);
      expect(find.text('Your food is packed and waiting for the rider'),
          findsOneWidget);
      expect(find.text('Preparing Your Food'), findsOneWidget);
    });

    testWidgets('a status the app does not know shows its raw value',
        (tester) async {
      await pumpTrackingScreen(
        tester,
        tracking: buildTrackedOrder(status: 'awaiting_courier'),
      );

      expect(find.text('Status: awaiting_courier'), findsOneWidget);
    });

    testWidgets('an order with no rider yet does not invent one',
        (tester) async {
      await pumpTrackingScreen(
        tester,
        tracking: buildTrackedOrder(
          status: 'confirmed',
          riderAssignmentStatus: null,
          riderFullName: null,
        ),
      );

      expect(find.text('Order Placed!'), findsOneWidget);
      expect(find.text('Test Rider'), findsNothing);
      expect(find.text('Ali Hassan (Senior Rider)'), findsNothing);
      expect(find.byIcon(Icons.call_rounded), findsNothing);
    });

    testWidgets('a rider appearing is announced, not swapped in silently',
        (tester) async {
      // Driven by hand so the two states are observed one after the other,
      // which is the point: the customer should be told the order moved.
      final controller = StreamController<OrderTracking?>();
      addTearDown(controller.close);

      final container = ProviderContainer(
        overrides: [
          trackedOrderIdProvider.overrideWith((_) => 'order-under-test'),
          activeOrderTrackingProvider.overrideWith(
            (ref) => controller.stream,
          ),
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
            home: const OrderTrackingScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      controller.add(buildTrackedOrder(
        status: 'confirmed',
        riderAssignmentStatus: null,
        riderFullName: null,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // First read: no banner, because nothing has actually changed yet.
      expect(find.text('Order Placed!'), findsOneWidget);
      expect(find.textContaining('just'), findsNothing);

      // The branch assigns a rider and moves the order out for delivery.
      controller.add(buildTrackedOrder(
        status: 'out_for_delivery',
        riderAssignmentStatus: 'picked_up',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // The header swapped to the new stage, the real rider is on screen, and
      // the customer was told rather than left to notice.
      expect(find.text('Out For Delivery!'), findsNWidgets(2));
      expect(find.text(riderName), findsOneWidget);
    });

    testWidgets('the bill number shown is the real one', (tester) async {
      await pumpTrackingScreen(tester);

      expect(find.text('MP-ABT-00042'), findsOneWidget);
      expect(find.textContaining('MP-9842'), findsNothing);
    });

    testWidgets('a failed read says so instead of showing a fake order',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          trackedOrderIdProvider.overrideWith((_) => 'order-under-test'),
          orderIdToTrackProvider.overrideWith((ref) async => null),
          activeOrderTrackingProvider.overrideWith(
            (ref) => Stream<OrderTracking?>.value(null),
          ),
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
            home: const OrderTrackingScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No orders to track yet'), findsOneWidget);
      expect(find.text('Test Rider'), findsNothing);
    });
  });
}
