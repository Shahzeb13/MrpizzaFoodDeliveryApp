/// Order models for the customer checkout flow.
library;

/// How an order is fulfilled.
enum OrderType {
  delivery('Delivery'),
  pickup('Pickup');

  final String label;
  const OrderType(this.label);

  String get dbValue => name;
}

/// Client-side order totals. Tax + delivery are computed here so the
/// summary shown in the UI always matches what gets inserted into `orders`.
///
/// The delivery fee is passed in rather than hardcoded: it is per-branch, set
/// by each branch manager in `store_settings`, and the two branches do not
/// charge the same. [branchDeliveryFee] must come from the branch that will
/// fulfil this order, not from a default.
class OrderTotals {
  static const double taxRate = 0.08;

  final double subtotal;
  final double tax;
  final double deliveryFee;

  OrderTotals({
    required this.subtotal,
    required OrderType orderType,
    required double branchDeliveryFee,
  })  : tax = subtotal * taxRate,
        deliveryFee =
            orderType == OrderType.pickup ? 0.0 : branchDeliveryFee;

  double get total => subtotal + tax + deliveryFee;
}

/// One cart line snapshot to insert into `order_items`.
class OrderItem {
  final String menuItemId;
  final int quantity;
  final double unitPrice;

  const OrderItem({
    required this.menuItemId,
    required this.quantity,
    required this.unitPrice,
  });

  Map<String, dynamic> toInsertMap(String orderId) {
    return {
      'order_id': orderId,
      'menu_item_id': menuItemId,
      'quantity': quantity,
      'price_at_order': unitPrice,
    };
  }
}

/// Row to insert into `orders` on checkout confirmation.
class Order {
  final String customerId;
  final String branchId;
  final String? addressId;
  final OrderType orderType;
  final String status;

  /// 'cod' or 'online' — how this order is being paid.
  ///
  /// Written on the order rather than inferred, because a cash order and an
  /// abandoned online payment both sit at payment_status = 'pending' and only
  /// this column tells them apart. Null is accepted by the database but is not
  /// a real option: every order placed by this app has chosen a method by the
  /// time its row is written.
  final String? paymentMethod;
  final OrderTotals totals;
  final List<OrderItem> items;

  /// The delivery contact, copied here at checkout. A rider has no access to the
  /// customer's `profiles` or `addresses` row, so these are the only copy of
  /// who to call and where to go. They also freeze what was actually ordered: a
  /// customer can edit their saved address afterwards, and the rider must still
  /// be sent to the address the order was placed with.
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;

  const Order({
    required this.customerId,
    required this.branchId,
    required this.addressId,
    required this.orderType,
    required this.totals,
    required this.items,
    this.status = 'confirmed',
    this.paymentMethod,
    this.customerName = '',
    this.customerPhone = '',
    this.deliveryAddress = '',
    this.deliveryLatitude,
    this.deliveryLongitude,
  });

  /// Row to insert into `orders` on checkout confirmation.
  ///
  /// `bill_serial_number` is deliberately omitted: the database fills it via
  /// the `orders_set_bill_serial_number` trigger, which allocates the next
  /// per-branch number atomically. The column is NOT NULL + UNIQUE, so
  /// generating it in the app would risk collisions on simultaneous orders.
  Map<String, dynamic> toInsertMap() {
    return {
      'customer_id': customerId,
      'branch_id': branchId,
      'address_id': addressId,
      'order_type': orderType.dbValue,
      'status': status,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      'subtotal': totals.subtotal,
      'tax': totals.tax,
      'delivery_charges': totals.deliveryFee,
      'total': totals.total,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'delivery_address': deliveryAddress,
      'delivery_latitude': deliveryLatitude,
      'delivery_longitude': deliveryLongitude,
    };
  }
}