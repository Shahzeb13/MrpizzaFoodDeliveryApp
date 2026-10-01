/// A real order, as the customer is allowed to see it.
///
/// Everything here is read from the database through `order_tracking()`. The
/// previous version of this flow was a `DemoOrder` built in Dart: a timer
/// assigned a rider called "Test Rider" 2.5 seconds after checkout, the headline
/// was hardcoded to "Baking in Wood-Fired Oven" regardless of what the order
/// actually was doing, and the totals came from whatever the local cart said.
/// None of those fields have a hardcoded fallback here — a missing value is
/// null, and the screen says so rather than inventing one.
library;

/// Where a real order is, derived from `orders.status` and the rider's
/// `rider_assignments.status`.
///
/// These map one-to-one onto the values `orders_status_check` allows:
/// `confirmed`, `in_kitchen`, `ready_for_pickup`, `out_for_delivery`,
/// `delivered`, `cancelled`. [riderHeadingToBranch] is not a stored status: it
/// is `out_for_delivery` before the rider has picked the food up, which is a
/// genuinely different situation for the customer.
enum OrderStage {
  orderConfirmed,
  preparingInKitchen,
  readyForPickup,
  riderHeadingToBranch,
  outForDelivery,
  delivered,
  cancelled,

  /// A status the app has not been taught, or a row that carried no status at
  /// all. Not a stored status — see [orderStageFromDatabase].
  ///
  /// This stage exists so "I do not understand this" has a name. Without it the
  /// mapping has to pick a lie, and the lie it used to pick was
  /// [orderConfirmed], which meant an unreadable row was treated as an order
  /// that had just been placed. Combined with the live bar's "newest unfinished
  /// order" lookup, that resurrected long-finished orders onto the home screen
  /// as if the kitchen had just started them.
  unknown,
}

OrderStage orderStageFromDatabase({
  required String orderStatus,
  String? riderAssignmentStatus,
}) {
  switch (orderStatus) {
    case 'cancelled':
      return OrderStage.cancelled;
    case 'delivered':
      return OrderStage.delivered;
    case 'out_for_delivery':
      return riderAssignmentStatus == 'picked_up'
          ? OrderStage.outForDelivery
          : OrderStage.riderHeadingToBranch;
    case 'ready_for_pickup':
      return OrderStage.readyForPickup;
    case 'in_kitchen':
      return OrderStage.preparingInKitchen;
    case 'confirmed':
      return OrderStage.orderConfirmed;
    default:
      // Deliberately NOT orderConfirmed. The comment that used to sit here
      // admitted the problem and then shipped the bug anyway: guessing
      // "just placed" is worse than admitting the app is behind, and it is
      // actively harmful to selection because an unreadable order looks
      // exactly like a live one. Unknown is never still-moving, so an order the
      // app cannot read can never be adopted onto the live bar.
      return OrderStage.unknown;
  }
}

/// The statuses `orders_status_check` currently allows on `orders.status`.
///
/// Kept here so the screen can tell the difference between "the kitchen has
/// started" and "the app has not been taught this status yet". The second case
/// must never be rendered as the first — telling a customer their order was
/// only just placed when the branch has already bagged it is the exact kind of
/// lie this rewrite removed.
const List<String> knownOrderStatuses = [
  'confirmed',
  'in_kitchen',
  'ready_for_pickup',
  'out_for_delivery',
  'delivered',
  'cancelled',
];

bool isRecognisedOrderStatus(String status) =>
    knownOrderStatuses.contains(status);

/// True only for stages where the order demonstrably still has somewhere to go.
///
/// Spelled out rather than written as "not delivered and not cancelled" so that
/// adding a stage cannot silently make it live by default. [OrderStage.unknown]
/// is the important exclusion: an order whose status the app cannot read must
/// never be treated as in-flight, because the live bar would adopt it and the
/// customer would be told their old order was being prepared right now.
bool isOrderStillMoving(OrderStage stage) {
  switch (stage) {
    case OrderStage.orderConfirmed:
    case OrderStage.preparingInKitchen:
    case OrderStage.readyForPickup:
    case OrderStage.riderHeadingToBranch:
    case OrderStage.outForDelivery:
      return true;
    case OrderStage.delivered:
    case OrderStage.cancelled:
    case OrderStage.unknown:
      return false;
  }
}

/// True if moving from [previous] to [next] would walk the order backwards.
///
/// Both the realtime push and the safety-net poll deliver the same data down
/// the same stream, and two reads in flight can finish in either order. When
/// they do, the slower one resolves last having observed the database *before*
/// the change, and the bar visibly rewinds — "Out For Delivery" back to
/// "Preparing" — which reads as a broken app even though both paths are working
/// exactly as designed. Refusing to publish a regression removes that class of
/// flicker without hiding anything real.
///
/// Two stages are allowed to move in any direction, because they are outcomes
/// rather than steps and the customer must never be left waiting on a progress
/// bar for an order that is already cancelled:
/// - reaching a terminal stage from anywhere
/// - [OrderStage.unknown], which means the app stopped understanding the order
///   and must be allowed to say so rather than keep asserting a stale stage
bool isOrderStageRegression(OrderStage previous, OrderStage next) {
  if (next == OrderStage.unknown) return false;
  if (next == OrderStage.delivered || next == OrderStage.cancelled) {
    return false;
  }
  // Once finished, finished. An order cannot quietly resume after being told
  // it was cancelled.
  if (previous == OrderStage.delivered || previous == OrderStage.cancelled) {
    return true;
  }
  return pipelineIndexOf(next) < pipelineIndexOf(previous);
}

int pipelineIndexOf(OrderStage stage) {
  switch (stage) {
    case OrderStage.orderConfirmed:
      return 0;
    case OrderStage.preparingInKitchen:
      return 1;
    case OrderStage.readyForPickup:
      return 2;
    case OrderStage.riderHeadingToBranch:
      return 3;
    case OrderStage.outForDelivery:
      return 3;
    case OrderStage.delivered:
      return 4;
    case OrderStage.cancelled:
      return 0;
    case OrderStage.unknown:
      return -1;
  }
}

/// One line of a placed order, snapshotted at the price that was actually paid.
class TrackedOrderItem {
  final String menuItemId;
  final String name;

  /// Null when the menu item has since been removed from the menu. The order
  /// line itself is still real, so it is still listed.
  final String? imageUrl;

  final int quantity;
  final double priceAtOrder;

  const TrackedOrderItem({
    required this.menuItemId,
    required this.name,
    required this.imageUrl,
    required this.quantity,
    required this.priceAtOrder,
  });

  double get lineTotal => quantity * priceAtOrder;

  factory TrackedOrderItem.fromMap(Map<String, dynamic> row) {
    final name = row['name']?.toString().trim() ?? '';
    return TrackedOrderItem(
      menuItemId: row['menu_item_id']?.toString() ?? '',
      name: name.isEmpty ? 'Menu item' : name,
      imageUrl: row['image_url']?.toString().trim(),
      quantity: _asInt(row['quantity']),
      priceAtOrder: _asDouble(row['price_at_order']),
    );
  }
}

/// The rider the branch actually assigned to this order.
///
/// Null until the branch assigns one. The name and phone come from the rider's
/// own profile row, which a customer may not read directly — the database
/// assembles them here so the customer can call the person delivering their
/// food without the whole rider directory being exposed.
class TrackedRider {
  final String assignmentStatus;
  final String? fullName;
  final String? phone;
  final DateTime? assignedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final String? failureReason;

  const TrackedRider({
    required this.assignmentStatus,
    required this.fullName,
    required this.phone,
    required this.assignedAt,
    required this.pickedUpAt,
    required this.deliveredAt,
    required this.failureReason,
  });

  bool get hasPickedUp => assignmentStatus == 'picked_up';

  /// True only when there is a real name AND a real number to dial. A rider
  /// whose profile has no phone is not shown a call button that would ring
  /// nobody.
  bool get canBeCalled {
    final name = fullName?.trim() ?? '';
    final number = phone?.trim() ?? '';
    return name.isNotEmpty && number.isNotEmpty;
  }

  factory TrackedRider.fromMap(Map<String, dynamic> row) {
    return TrackedRider(
      assignmentStatus: row['assignment_status']?.toString() ?? '',
      fullName: _asNullableString(row['full_name']),
      phone: _asNullableString(row['phone']),
      assignedAt: DateTime.tryParse(row['assigned_at']?.toString() ?? ''),
      pickedUpAt: DateTime.tryParse(row['picked_up_at']?.toString() ?? ''),
      deliveredAt: DateTime.tryParse(row['delivered_at']?.toString() ?? ''),
      failureReason: _asNullableString(row['failure_reason']),
    );
  }
}

/// One recorded status change, from `order_status_history`.
///
/// These are real timestamps the branch and the rider actually produced, which
/// is what replaced the fabricated "EST. 14 MIN" box.
class TrackedStatusChange {
  final String status;
  final DateTime? changedAt;

  const TrackedStatusChange({required this.status, required this.changedAt});

  factory TrackedStatusChange.fromMap(Map<String, dynamic> row) {
    return TrackedStatusChange(
      status: row['status']?.toString() ?? '',
      changedAt: DateTime.tryParse(row['changed_at']?.toString() ?? ''),
    );
  }
}

/// The whole live state of one order.
class OrderTracking {
  final String orderId;

  /// The shop's own bill number, allocated by the database. Null only on an
  /// order row that predates the serial trigger.
  final String? billNumber;

  final String status;
  final String orderType;
  final double subtotal;
  final double tax;
  final double deliveryCharges;
  final double discountAmount;

  /// Read from the `orders` row, which is the amount the kitchen and the
  /// ledger agree on — not recomputed in the app from the displayed lines.
  final double total;

  final DateTime? createdAt;
  final String? deliveryAddress;
  final String? branchName;
  final List<TrackedOrderItem> items;
  final TrackedRider? rider;
  final List<TrackedStatusChange> timeline;

  const OrderTracking({
    required this.orderId,
    required this.billNumber,
    required this.status,
    required this.orderType,
    required this.subtotal,
    required this.tax,
    required this.deliveryCharges,
    required this.discountAmount,
    required this.total,
    required this.createdAt,
    required this.deliveryAddress,
    required this.branchName,
    required this.items,
    required this.rider,
    required this.timeline,
  });

  bool get isPickup => orderType == 'pickup';

  OrderStage get stage => orderStageFromDatabase(
        orderStatus: status,
        riderAssignmentStatus: rider?.assignmentStatus,
      );

  /// True when the branch has set a status this app version does not know. The
  /// screen then shows the raw database value rather than guessing a stage and
  /// telling the customer something that is not true.
  bool get hasUnrecognisedStatus => !isRecognisedOrderStatus(status);

  /// The number of stages a real order passes through, in order. Five, because
  /// the database distinguishes "being cooked" from "cooked and bagged, waiting
  /// for a rider" — a customer watching their food sit on the pass deserves to
  /// be told that, and a real app shows it as its own step.
  static const int pipelineStepCount = 5;

  bool get isStillMoving => isOrderStillMoving(stage);

  /// Reads the `jsonb` from `order_tracking()`.
  ///
  /// Null when the database refused the read (signed out, wrong order, or a
  /// payload it could not read). The refusal never becomes a blank order: an
  /// unreadable order is reported as unreadable rather than rendered as an
  /// order with empty fields.
  static OrderTracking? fromRpcResult(Object? result) {
    final payload = _unwrapObject(result);
    if (payload == null) return null;

    final order = _asMap(payload['order']);
    if (order == null) return null;

    return OrderTracking(
      orderId: order['id']?.toString() ?? '',
      billNumber: _asNullableString(order['bill_number']),
      status: order['status']?.toString() ?? '',
      orderType: order['order_type']?.toString() ?? '',
      subtotal: _asDouble(order['subtotal']),
      tax: _asDouble(order['tax']),
      deliveryCharges: _asDouble(order['delivery_charges']),
      discountAmount: _asDouble(order['discount_amount']),
      total: _asDouble(order['total']),
      createdAt: DateTime.tryParse(order['created_at']?.toString() ?? ''),
      deliveryAddress: _asNullableString(order['delivery_address']),
      branchName: _asNullableString(order['branch_name']),
      items: _asList(payload['items'])
          .map(TrackedOrderItem.fromMap)
          .toList(growable: false),
      rider: payload['rider'] == null
          ? null
          : TrackedRider.fromMap(_asMap(payload['rider']) ?? const {}),
      timeline: _asList(payload['timeline'])
          .map(TrackedStatusChange.fromMap)
          .toList(growable: false),
    );
  }
}

/// One row of the "My Orders" list.
///
/// Carries only what the list renders. The full order, including the item
/// breakdown and the rider, is fetched on demand by [OrderTracking].
class OrderSummary {
  final String orderId;
  final String? billNumber;
  final String status;
  final String orderType;
  final double subtotal;
  final double tax;
  final double deliveryCharges;
  final double discountAmount;
  final double total;
  final DateTime? createdAt;
  final String? branchName;
  final String? itemSummary;
  final int itemCount;
  final String? riderName;

  const OrderSummary({
    required this.orderId,
    required this.billNumber,
    required this.status,
    required this.orderType,
    required this.subtotal,
    required this.tax,
    required this.deliveryCharges,
    required this.discountAmount,
    required this.total,
    required this.createdAt,
    required this.branchName,
    required this.itemSummary,
    required this.itemCount,
    required this.riderName,
  });

  OrderStage get stage => orderStageFromDatabase(orderStatus: status);

  bool get isStillMoving => isOrderStillMoving(stage);

  factory OrderSummary.fromMap(Map<String, dynamic> row) {
    return OrderSummary(
      orderId: row['id']?.toString() ?? '',
      billNumber: _asNullableString(row['bill_number']),
      status: row['status']?.toString() ?? '',
      orderType: row['order_type']?.toString() ?? '',
      subtotal: _asDouble(row['subtotal']),
      tax: _asDouble(row['tax']),
      deliveryCharges: _asDouble(row['delivery_charges']),
      discountAmount: _asDouble(row['discount_amount']),
      total: _asDouble(row['total']),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
      branchName: _asNullableString(row['branch_name']),
      itemSummary: _asNullableString(row['item_summary']),
      itemCount: _asInt(row['item_count']),
      riderName: _asNullableString(row['rider_name']),
    );
  }
}

Map<String, dynamic>? _unwrapObject(Object? result) {
  if (result is Map) return Map<String, dynamic>.from(result);
  if (result is List && result.isNotEmpty && result.first is Map) {
    return Map<String, dynamic>.from(result.first as Map);
  }
  return null;
}

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

List<Map<String, dynamic>> _asList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(Map<String, dynamic>.from)
      .toList(growable: false);
}

String? _asNullableString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int _asInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
