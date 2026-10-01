import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/orders/models/order_tracking.dart';
import 'package:mrpizza/features/orders/presentation/order_status_copy.dart';

/// `orders_status_check` allows six values. The branch added `ready_for_pickup`
/// to them, which is the difference between "the kitchen is on it" and "your
/// food is bagged and waiting for a rider" — a stage a customer can actually
/// feel, so it has to be its own step and not a silent fall-through.
void main() {
  group('the stage comes from the stored status', () {
    test('every status the check constraint allows has its own stage', () {
      expect(knownOrderStatuses, [
        'confirmed',
        'in_kitchen',
        'ready_for_pickup',
        'out_for_delivery',
        'delivered',
        'cancelled',
      ]);

      expect(orderStageFromDatabase(orderStatus: 'confirmed'),
          OrderStage.orderConfirmed);
      expect(orderStageFromDatabase(orderStatus: 'in_kitchen'),
          OrderStage.preparingInKitchen);
      expect(orderStageFromDatabase(orderStatus: 'ready_for_pickup'),
          OrderStage.readyForPickup);
      expect(orderStageFromDatabase(orderStatus: 'delivered'),
          OrderStage.delivered);
      expect(orderStageFromDatabase(orderStatus: 'cancelled'),
          OrderStage.cancelled);
    });

    test('ready_for_pickup is its own stage, not "being cooked"', () {
      final stage = orderStageFromDatabase(orderStatus: 'ready_for_pickup');

      expect(stage, OrderStage.readyForPickup);
      expect(stage, isNot(OrderStage.preparingInKitchen));
      expect(stage, isNot(OrderStage.orderConfirmed));
    });

    test('out_for_delivery splits on whether the rider has picked up', () {
      expect(
        orderStageFromDatabase(
          orderStatus: 'out_for_delivery',
          riderAssignmentStatus: 'picked_up',
        ),
        OrderStage.outForDelivery,
      );
      expect(
        orderStageFromDatabase(
          orderStatus: 'out_for_delivery',
          riderAssignmentStatus: 'assigned',
        ),
        OrderStage.riderHeadingToBranch,
      );
      expect(
        orderStageFromDatabase(orderStatus: 'out_for_delivery'),
        OrderStage.riderHeadingToBranch,
      );
    });
  });

  group('the pipeline advances one step at a time', () {
    test('each stage lights up exactly the steps behind it', () {
      expect(pipelineProgressFor(OrderStage.orderConfirmed), 0);
      expect(pipelineProgressFor(OrderStage.preparingInKitchen), 1);
      expect(pipelineProgressFor(OrderStage.readyForPickup), 2);
      expect(pipelineProgressFor(OrderStage.riderHeadingToBranch), 3);
      expect(pipelineProgressFor(OrderStage.outForDelivery), 3);
      expect(
        pipelineProgressFor(OrderStage.delivered),
        OrderTracking.pipelineStepCount,
      );
    });

    test('the pipeline has five steps so the new status has a home', () {
      expect(OrderTracking.pipelineStepCount, 5);
    });

    test('a cancelled order does not claim progress', () {
      expect(pipelineProgressFor(OrderStage.cancelled), 0);
    });
  });

  group('the wording is honest about what the database holds', () {
    test('ready_for_pickup reads as its own thing', () {
      expect(statusLabel('ready_for_pickup'), 'Ready for pickup');
    });

    test('an unknown status is shown as stored, not mistranslated', () {
      // A status added in the database tomorrow must not be bucketed into one
      // the app already knows.
      expect(statusLabel('awaiting_courier'), 'awaiting_courier');
    });

    test('a rider who has picked up is told so plainly', () {
      expect(
        riderAssignmentLabel('picked_up'),
        'Has your order and is on the way to you',
      );
    });
  });

  group('an unreadable status is never mistaken for a live order', () {
    test('an unrecognised status is unknown, not "just placed"', () {
      // The regression this guards. This used to return orderConfirmed, which
      // was indistinguishable from a brand new order — so the live bar adopted
      // long-finished orders whose status it could not read and announced they
      // were being prepared.
      expect(
        orderStageFromDatabase(orderStatus: 'awaiting_courier'),
        OrderStage.unknown,
      );
      expect(orderStageFromDatabase(orderStatus: ''), OrderStage.unknown);
      expect(orderStageFromDatabase(orderStatus: 'PENDING'),
          OrderStage.unknown);
    });

    test('an unknown status is never still moving', () {
      // The single most important property: fail closed, so an order the app
      // cannot read can never be selected as something in flight.
      expect(isOrderStillMoving(OrderStage.unknown), isFalse);
      expect(isRecognisedOrderStatus('awaiting_courier'), isFalse);
    });

    test('an unknown status claims no pipeline progress', () {
      expect(pipelineProgressFor(OrderStage.unknown), 0);
    });

    test('an unknown status admits itself instead of inventing a stage', () {
      final tracking = OrderTracking(
        orderId: '11111111-1111-1111-1111-111111111111',
        billNumber: 'MP-ABT-00042',
        status: 'awaiting_courier',
        orderType: 'delivery',
        subtotal: 100,
        tax: 8,
        deliveryCharges: 0,
        discountAmount: 0,
        total: 108,
        createdAt: DateTime(2026, 9, 29, 14, 15),
        deliveryAddress: 'Somewhere in Abbottabad',
        branchName: 'Mr. Pizza - Abbottabad',
        items: const [],
        rider: null,
        timeline: const [],
      );

      expect(stageHeadline(OrderStage.unknown, tracking), 'Status Unavailable');
      expect(
        stageSubtitle(OrderStage.unknown, tracking),
        contains('awaiting_courier'),
      );
    });

    test('a missing status does not render as an empty quote', () {
      final tracking = OrderTracking(
        orderId: '11111111-1111-1111-1111-111111111111',
        billNumber: null,
        status: '',
        orderType: 'delivery',
        subtotal: 100,
        tax: 8,
        deliveryCharges: 0,
        discountAmount: 0,
        total: 108,
        createdAt: DateTime(2026, 9, 29, 14, 15),
        deliveryAddress: 'Somewhere in Abbottabad',
        branchName: 'Mr. Pizza - Abbottabad',
        items: const [],
        rider: null,
        timeline: const [],
      );

      expect(stageSubtitle(OrderStage.unknown, tracking),
          'This order has no status saved against it. Tap for details.');
    });
  });

  group('a stage never goes backwards', () {
    // Realtime and the safety-net poll both publish into the same stream, so a
    // slow read can resolve after a fast one and try to rewind the customer to
    // a stage they have already passed. These are the rules that stop it.
    test('moving forward is not a regression', () {
      expect(
        isOrderStageRegression(
          OrderStage.preparingInKitchen,
          OrderStage.outForDelivery,
        ),
        isFalse,
      );
      expect(
        isOrderStageRegression(
          OrderStage.riderHeadingToBranch,
          OrderStage.outForDelivery,
        ),
        isFalse,
      );
    });

    test('moving backwards is a regression', () {
      expect(
        isOrderStageRegression(
          OrderStage.outForDelivery,
          OrderStage.preparingInKitchen,
        ),
        isTrue,
      );
      expect(
        isOrderStageRegression(
          OrderStage.readyForPickup,
          OrderStage.orderConfirmed,
        ),
        isTrue,
      );
    });

    test('reaching a finished stage is never a regression', () {
      // From anywhere, including backwards: a cancellation can arrive at any
      // point, and a customer must never be left on a moving progress bar for
      // an order that is already dead.
      expect(
        isOrderStageRegression(
          OrderStage.outForDelivery,
          OrderStage.cancelled,
        ),
        isFalse,
      );
      expect(
        isOrderStageRegression(
          OrderStage.orderConfirmed,
          OrderStage.delivered,
        ),
        isFalse,
      );
    });

    test('a finished order never resumes', () {
      expect(
        isOrderStageRegression(
          OrderStage.cancelled,
          OrderStage.preparingInKitchen,
        ),
        isTrue,
      );
      expect(
        isOrderStageRegression(
          OrderStage.delivered,
          OrderStage.outForDelivery,
        ),
        isTrue,
      );
    });

    test('an unknown stage always wins, because it admits ignorance', () {
      // Hiding "we cannot read this order" behind a stale in-flight stage would
      // be the app asserting something it has stopped being able to verify.
      expect(
        isOrderStageRegression(OrderStage.outForDelivery, OrderStage.unknown),
        isFalse,
      );
      expect(
        isOrderStageRegression(OrderStage.cancelled, OrderStage.unknown),
        isFalse,
      );
    });
  });
}
