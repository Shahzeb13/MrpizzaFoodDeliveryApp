import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/rider/models/rider_delivery.dart';

Map<String, dynamic> _row({
  String status = 'accepted',
  String? customerName = 'Usama Khan',
  String? customerPhone = '03001234567',
  String? deliveryAddress = 'Mandian, Abbottabad',
}) =>
    {
      'assignment_id': 'a1',
      'assignment_status': status,
      'order_id': 'o1',
      'bill_number': '#MP-84910',
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'delivery_address': deliveryAddress,
      'delivery_latitude': 34.1688,
      'delivery_longitude': 73.2215,
      'branch_name': 'Mr. Pizza – Abbottabad',
      'branch_address': 'Niazi Road, Abbottabad',
      'item_summary': '2x Zinger, 1x Coke',
      'item_count': 3,
      'assigned_at': '2026-09-28T10:00:00Z',
      'picked_up_at': null,
      'delivered_at': null,
    };

void main() {
  test('reads a full assignment row', () {
    final delivery = RiderDelivery.fromAssignmentRow(_row());
    expect(delivery.assignmentId, 'a1');
    expect(delivery.billNumber, '#MP-84910');
    expect(delivery.customerName, 'Usama Khan');
    expect(delivery.deliveryLatitude, 34.1688);
    expect(delivery.itemCount, 3);
  });

  test('an order placed before the snapshot has no usable contact details', () {
    // Every snapshot column is null on an order placed before the migration,
    // coordinates included.
    final delivery = RiderDelivery.fromAssignmentRow({
      ..._row(),
      'customer_name': null,
      'customer_phone': null,
      'delivery_address': null,
      'delivery_latitude': null,
      'delivery_longitude': null,
    });
    expect(delivery.hasContactDetails, isFalse);
    expect(delivery.customerName, '');
    expect(delivery.deliveryAddress, '');
    expect(delivery.deliveryLatitude, isNull);
  });

  test('classifies each lifecycle status', () {
    expect(
        RiderDelivery.fromAssignmentRow(_row(status: 'assigned')).isOffer, isTrue);
    expect(
        RiderDelivery.fromAssignmentRow(_row(status: 'accepted')).isActive,
        isTrue);
    expect(
        RiderDelivery.fromAssignmentRow(_row(status: 'picked_up')).isActive,
        isTrue);
    for (final finished in ['delivered', 'declined', 'failed']) {
      expect(
        RiderDelivery.fromAssignmentRow(_row(status: finished)).isHistory,
        isTrue,
        reason: '$finished should be history',
      );
    }
  });

  test('an unrecognised status is history, so it is never offered as work', () {
    final delivery = RiderDelivery.fromAssignmentRow(_row(status: 'wat'));
    expect(delivery.isHistory, isTrue);
    expect(delivery.isOffer, isFalse);
    expect(delivery.isActive, isFalse);
  });

  test('the three buckets never overlap', () {
    for (final status in [
      'assigned', 'accepted', 'picked_up', 'delivered', 'declined', 'failed'
    ]) {
      final d = RiderDelivery.fromAssignmentRow(_row(status: status));
      final buckets = [d.isOffer, d.isActive, d.isHistory].where((b) => b).length;
      expect(buckets, 1, reason: '$status landed in $buckets buckets');
    }
  });

  test('a maps link needs coordinates and is null without them', () {
    final withCoordinates = RiderDelivery.fromAssignmentRow(_row());
    expect(withCoordinates.mapsUrl, isNotNull);
    expect(withCoordinates.mapsUrl, contains('34.1688'));

    final withoutCoordinates = RiderDelivery.fromAssignmentRow({
      ..._row(),
      'delivery_latitude': null,
      'delivery_longitude': null,
    });
    expect(withoutCoordinates.mapsUrl, isNull);
  });
}
