import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/orders/models/order_tracking.dart';
import 'package:mrpizza/features/payment/start_checkout_guarded.dart';

/// A customer ordering again while an order is still going out gets a warning,
/// not a refusal.
///
/// The bound is the part worth testing. An unbounded warning is a softer trap
/// than a block but the same trap: this project's database has held orders open
/// in `confirmed` indefinitely, so a check with no age limit would ask that
/// customer about a stuck order on every checkout forever, with no way to make
/// it stop.
OrderSummary order({
  required String id,
  required String status,
  DateTime? createdAt,
}) {
  return OrderSummary(
    orderId: id,
    billNumber: 'MP-ABT-00042',
    status: status,
    orderType: 'delivery',
    subtotal: 100,
    tax: 8,
    deliveryCharges: 0,
    discountAmount: 0,
    total: 108,
    createdAt: createdAt,
    branchName: 'Mr. Pizza - Abbottabad',
    itemSummary: '1x Chicken Tikka Supreme',
    itemCount: 1,
    riderName: null,
  );
}

void main() {
  final now = DateTime(2026, 10, 1, 14, 0);

  group('a real order in progress is recognised', () {
    test('an order from twenty minutes ago counts', () {
      final found = findOrderInProgress(
        [order(id: 'a', status: 'in_kitchen', createdAt: now.subtract(const Duration(minutes: 20)))],
        now,
      );

      expect(found?.orderId, 'a');
    });

    test('every unfinished status counts', () {
      for (final status in [
        'confirmed',
        'in_kitchen',
        'ready_for_pickup',
        'out_for_delivery',
      ]) {
        expect(
          findOrderInProgress(
            [order(id: 'a', status: status, createdAt: now)],
            now,
          ),
          isNotNull,
          reason: '$status should count as in progress',
        );
      }
    });

    test('finished orders do not count', () {
      // The common case by far. Most customers have finished orders in their
      // history and must never be warned about them.
      expect(
        findOrderInProgress(
          [order(id: 'a', status: 'delivered', createdAt: now)],
          now,
        ),
        isNull,
      );
      expect(
        findOrderInProgress(
          [order(id: 'a', status: 'cancelled', createdAt: now)],
          now,
        ),
        isNull,
      );
    });
  });

  group('stuck data does not nag forever', () {
    test('an order older than the window is ignored', () {
      // The trap this exists to avoid. A branch that never closed an order
      // would otherwise leave the customer warned about it forever.
      expect(
        findOrderInProgress(
          [
            order(
              id: 'stuck',
              status: 'confirmed',
              createdAt: now.subtract(const Duration(days: 3)),
            ),
          ],
          now,
        ),
        isNull,
      );
    });

    test('just inside the window still counts', () {
      expect(
        findOrderInProgress(
          [
            order(
              id: 'slow',
              status: 'in_kitchen',
              createdAt: now.subtract(const Duration(hours: 2, minutes: 50)),
            ),
          ],
          now,
        ),
        isNotNull,
      );
    });

    test('an order with no timestamp is ignored', () {
      // Cannot be age-checked, so it cannot be shown to be real either.
      expect(
        findOrderInProgress([order(id: 'a', status: 'confirmed')], now),
        isNull,
      );
    });
  });

  test('the newest unfinished order is the one reported', () {
    final found = findOrderInProgress(
      [
        order(id: 'older', status: 'in_kitchen', createdAt: now.subtract(const Duration(minutes: 50))),
        order(id: 'newer', status: 'out_for_delivery', createdAt: now.subtract(const Duration(minutes: 10))),
      ],
      now,
    );

    expect(found?.orderId, 'newer');
  });
}