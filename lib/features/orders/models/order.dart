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
class OrderTotals {
  static const double taxRate = 0.08;
  static const double deliveryCharge = 150.0;

  final double subtotal;
  final double tax;
  final double deliveryFee;

  OrderTotals({
    required this.subtotal,
    required OrderType orderType,
  })  : tax = subtotal * taxRate,
        deliveryFee = orderType == OrderType.pickup ? 0.0 : deliveryCharge;

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
  final OrderTotals totals;
  final List<OrderItem> items;

  const Order({
    required this.customerId,
    required this.branchId,
    required this.addressId,
    required this.orderType,
    required this.totals,
    required this.items,
    this.status = 'confirmed',
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
      'subtotal': totals.subtotal,
      'tax': totals.tax,
      'delivery_charges': totals.deliveryFee,
      'total': totals.total,
    };
  }
}