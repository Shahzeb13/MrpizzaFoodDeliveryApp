import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/rider/logic/delivery_actions.dart';
import 'package:mrpizza/features/rider/models/rider_delivery.dart';

RiderDelivery _delivery(String status, {String id = 'a'}) => RiderDelivery(
      assignmentId: id,
      orderId: 'o$id',
      billNumber: '#$id',
      assignmentStatus: status,
      customerName: 'Usama',
      customerPhone: '0300',
      deliveryAddress: 'Mandian',
      deliveryLatitude: 34.16,
      deliveryLongitude: 73.22,
      branchName: 'Abbottabad',
      branchAddress: 'Niazi Road',
      itemSummary: '2x Zinger',
      itemCount: 2,
      assignedAt: DateTime(2026, 9, 28),
      pickedUpAt: null,
      deliveredAt: null,
    );

void main() {
  group('the primary button follows the lifecycle', () {
    test('an accepted job offers pickup, not delivery', () {
      final button = primaryActionFor(_delivery('accepted'))!;
      expect(button.action, RiderAction.markPickedUp);
      expect(button.label, "I've Picked Up");
    });

    test('a picked up job offers completion', () {
      final button = primaryActionFor(_delivery('picked_up'))!;
      expect(button.action, RiderAction.complete);
      expect(button.label, 'Mark Delivered');
    });

    test('an offer has no single primary action, it is accepted or declined', () {
      expect(primaryActionFor(_delivery('assigned')), isNull);
    });

    test('a finished job has no primary action', () {
      for (final status in ['delivered', 'declined', 'failed', 'wat']) {
        expect(primaryActionFor(_delivery(status)), isNull,
            reason: '$status should offer no action');
      }
    });
  });

  group('the dashboard buckets never overlap', () {
    final all = [
      _delivery('assigned', id: '1'),
      _delivery('accepted', id: '2'),
      _delivery('picked_up', id: '3'),
      _delivery('delivered', id: '4'),
      _delivery('declined', id: '5'),
      _delivery('failed', id: '6'),
    ];

    test('every delivery lands in exactly one bucket', () {
      final offers = pendingOffersFor(all).map((d) => d.assignmentId).toSet();
      final active = activeDeliveryFor(all);
      final history =
          deliveredHistoryFor(all).map((d) => d.assignmentId).toSet();

      final placed = <String>{...offers, ...history};
      if (active != null) placed.add(active.assignmentId);

      expect(placed, hasLength(all.length),
          reason: 'some delivery was in no bucket or more than one');
      for (final delivery in all) {
        final buckets = [
          if (offers.contains(delivery.assignmentId)) 1 else 0,
          if (active?.assignmentId == delivery.assignmentId) 1 else 0,
          if (history.contains(delivery.assignmentId)) 1 else 0,
        ].reduce((a, b) => a + b);
        expect(buckets, 1,
            reason: '${delivery.assignmentId} landed in $buckets buckets');
      }
    });

    test('only assigned jobs are offered', () {
      expect(pendingOffersFor(all).map((d) => d.assignmentId), ['1']);
    });

    test('the active job is the accepted one, and pickup is not a second one', () {
      expect(activeDeliveryFor(all)?.assignmentId, '2');
      expect(
          activeDeliveryFor([_delivery('picked_up', id: '3')])?.assignmentId,
          '3');
    });

    test('history is everything that has ended', () {
      expect(
        deliveredHistoryFor(all).map((d) => d.assignmentId).toSet(),
        {'4', '5', '6'},
      );
    });

    test('history is newest first', () {
      final older = RiderDelivery(
        assignmentId: 'old',
        orderId: 'oold',
        billNumber: '#old',
        assignmentStatus: 'delivered',
        customerName: '',
        customerPhone: '',
        deliveryAddress: '',
        deliveryLatitude: null,
        deliveryLongitude: null,
        branchName: '',
        branchAddress: '',
        itemSummary: '',
        itemCount: 0,
        assignedAt: DateTime(2026, 9, 20),
        pickedUpAt: null,
        deliveredAt: DateTime(2026, 9, 20, 12),
      );
      final newer = RiderDelivery(
        assignmentId: 'new',
        orderId: 'onew',
        billNumber: '#new',
        assignmentStatus: 'delivered',
        customerName: '',
        customerPhone: '',
        deliveryAddress: '',
        deliveryLatitude: null,
        deliveryLongitude: null,
        branchName: '',
        branchAddress: '',
        itemSummary: '',
        itemCount: 0,
        assignedAt: DateTime(2026, 9, 28),
        pickedUpAt: null,
        deliveredAt: DateTime(2026, 9, 28, 12),
      );

      expect(
        deliveredHistoryFor([older, newer]).map((d) => d.assignmentId),
        ['new', 'old'],
      );
    });

    test('no job means no active job and no crash', () {
      expect(activeDeliveryFor([]), isNull);
      expect(pendingOffersFor([]), isEmpty);
      expect(deliveredHistoryFor([]), isEmpty);
    });
  });

  group('earnings count delivered jobs only', () {
    test('uses the configured rate, not the delivery charge', () {
      final earnings = earningsFor(
        [_delivery('delivered', id: '1'), _delivery('delivered', id: '2')],
        250,
      );
      expect(earnings, 500);
    });

    test('ignores offers, active and failed jobs', () {
      final earnings = earningsFor([
        _delivery('assigned', id: '1'),
        _delivery('accepted', id: '2'),
        _delivery('picked_up', id: '3'),
        _delivery('failed', id: '4'),
        _delivery('declined', id: '5'),
      ], 250);
      expect(earnings, 0);
    });

    test('an unavailable rate does not invent money', () {
      expect(earningsFor([_delivery('delivered')], 0), 0);
      expect(completedCountFor([_delivery('delivered')]), 1);
    });
  });
}
