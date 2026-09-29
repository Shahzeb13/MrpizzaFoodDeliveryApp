import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/orders/models/order.dart';

Order _order({
  String customerName = '',
  String customerPhone = '',
  String deliveryAddress = '',
  double? deliveryLatitude,
  double? deliveryLongitude,
  String? addressId = 'a1',
  OrderType orderType = OrderType.delivery,
}) =>
    Order(
      customerId: 'c1',
      branchId: 'b1',
      addressId: addressId,
      orderType: orderType,
      totals: OrderTotals(subtotal: 1000, orderType: orderType),
      items: const [],
      customerName: customerName,
      customerPhone: customerPhone,
      deliveryAddress: deliveryAddress,
      deliveryLatitude: deliveryLatitude,
      deliveryLongitude: deliveryLongitude,
    );

void main() {
  test('toInsertMap carries the delivery contact snapshot', () {
    final map = _order(
      customerName: 'Usama Khan',
      customerPhone: '03001234567',
      deliveryAddress: 'Mandian, Abbottabad',
      deliveryLatitude: 34.1688,
      deliveryLongitude: 73.2215,
    ).toInsertMap();

    expect(map['customer_name'], 'Usama Khan');
    expect(map['customer_phone'], '03001234567');
    expect(map['delivery_address'], 'Mandian, Abbottabad');
    expect(map['delivery_latitude'], 34.1688);
    expect(map['delivery_longitude'], 73.2215);
  });

  test('a pickup order still records the snapshot columns, as empty values', () {
    final map = _order(
      addressId: null,
      orderType: OrderType.pickup,
    ).toInsertMap();

    expect(map['customer_name'], '');
    expect(map['customer_phone'], '');
    expect(map['delivery_address'], '');
    expect(map['delivery_latitude'], isNull);
    expect(map['delivery_longitude'], isNull);
    expect(map['address_id'], isNull);
  });

  test('a hand typed address with no coordinates writes nulls, not zeros', () {
    final map = _order(
      deliveryAddress: 'Near the big tree, Mandian',
    ).toInsertMap();

    expect(map['delivery_address'], 'Near the big tree, Mandian');
    expect(map['delivery_latitude'], isNull);
    expect(map['delivery_longitude'], isNull);
  });

  test('bill_serial_number is still not generated in the app', () {
    expect(_order().toInsertMap().containsKey('bill_serial_number'), isFalse);
  });

  test('the existing order fields are untouched by the snapshot', () {
    final map = _order(customerName: 'Usama Khan').toInsertMap();

    expect(map['customer_id'], 'c1');
    expect(map['branch_id'], 'b1');
    expect(map['order_type'], 'delivery');
    expect(map['status'], 'confirmed');
    expect(map['subtotal'], 1000);
    expect(map['tax'], OrderTotals.taxRate * 1000);
    expect(map['delivery_charges'], OrderTotals.deliveryCharge);
    expect(map['total'], 1000 + (OrderTotals.taxRate * 1000) + OrderTotals.deliveryCharge);
  });
}
