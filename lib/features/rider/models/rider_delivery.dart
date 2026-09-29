/// One delivery assignment, joined to the order and branch it refers to.
///
/// The customer name, phone and address come from the snapshot columns on
/// `orders`, never from a customer profile lookup: a rider has no RLS access to
/// customer rows, and the address the customer had when they ordered is the one
/// the rider must deliver to.
class RiderDelivery {
  final String assignmentId;
  final String orderId;
  final String billNumber;
  final String assignmentStatus;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String branchName;
  final String branchAddress;
  final String itemSummary;
  final int itemCount;
  final DateTime? assignedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;

  const RiderDelivery({
    required this.assignmentId,
    required this.orderId,
    required this.billNumber,
    required this.assignmentStatus,
    required this.customerName,
    required this.customerPhone,
    required this.deliveryAddress,
    required this.deliveryLatitude,
    required this.deliveryLongitude,
    required this.branchName,
    required this.branchAddress,
    required this.itemSummary,
    required this.itemCount,
    required this.assignedAt,
    required this.pickedUpAt,
    required this.deliveredAt,
  });

  factory RiderDelivery.fromAssignmentRow(Map<String, dynamic> row) {
    return RiderDelivery(
      assignmentId: row['assignment_id'] as String,
      orderId: row['order_id'] as String,
      billNumber: (row['bill_number'] as String?) ?? '',
      assignmentStatus: (row['assignment_status'] as String?) ?? '',
      customerName: (row['customer_name'] as String?) ?? '',
      customerPhone: (row['customer_phone'] as String?) ?? '',
      deliveryAddress: (row['delivery_address'] as String?) ?? '',
      deliveryLatitude: (row['delivery_latitude'] as num?)?.toDouble(),
      deliveryLongitude: (row['delivery_longitude'] as num?)?.toDouble(),
      branchName: (row['branch_name'] as String?) ?? '',
      branchAddress: (row['branch_address'] as String?) ?? '',
      itemSummary: (row['item_summary'] as String?) ?? '',
      itemCount: (row['item_count'] as num?)?.toInt() ?? 0,
      assignedAt: parseAssignmentTimestamp(row['assigned_at']),
      pickedUpAt: parseAssignmentTimestamp(row['picked_up_at']),
      deliveredAt: parseAssignmentTimestamp(row['delivered_at']),
    );
  }

  /// A job waiting for this rider to accept or decline it.
  bool get isOffer => assignmentStatus == 'assigned';

  /// A job this rider is currently doing.
  bool get isActive =>
      assignmentStatus == 'accepted' || assignmentStatus == 'picked_up';

  /// A job that has ended, one way or another.
  ///
  /// Anything unrecognised counts as history so an unknown status is never
  /// offered to a rider as work they might take.
  bool get isHistory => !isOffer && !isActive;

  /// False when there is nothing to show a rider: no phone to call and no
  /// address to deliver to. An order placed before the snapshot columns
  /// existed is the case that matters. Note this is NOT about coordinates: an
  /// address typed by hand has no coordinates but is still deliverable.
  bool get hasContactDetails =>
      customerPhone.isNotEmpty || deliveryAddress.isNotEmpty;

  /// True when there is a number to dial, which is separate from having an
  /// address — an order can be deliverable but not callable.
  bool get hasPhoneNumber => customerPhone.trim().isNotEmpty;

  /// A `geo:` URI for the delivery address, or null when there are no
  /// coordinates to point at.
  String? get mapsUrl {
    if (deliveryLatitude == null || deliveryLongitude == null) return null;
    return 'geo:$deliveryLatitude,$deliveryLongitude'
        '?q=${Uri.encodeComponent('$deliveryLatitude,$deliveryLongitude')}';
  }
}

/// Reads a Postgres timestamp, tolerating both `timestamptz` strings and values
/// the client has already decoded into a [DateTime].
DateTime? parseAssignmentTimestamp(Object? value) {
  if (value is DateTime) return value.toLocal();
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toLocal();
}
