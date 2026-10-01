import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/app_theme.dart';
import 'package:mrpizza/features/orders/data/order_tracking_repository.dart';
import 'package:mrpizza/features/orders/models/order_tracking.dart';
import 'package:mrpizza/features/orders/providers/order_tracking_provider.dart';
import 'package:mrpizza/features/orders/screens/my_orders_screen.dart';

/// My Orders used to read `my_orders()` exactly once, on open, and then sit on
/// that snapshot for as long as the screen was alive.
///
/// The visible symptom was two screens disagreeing about the same order. The
/// home bar follows its order in realtime, so it said "Order Cancelled" the
/// instant the branch cancelled — while the list, having fetched the status
/// half a minute earlier, went on saying "Preparing in the kitchen". A customer
/// who opened My Orders to double-check the bar was looking at a stale copy of
/// the very thing the bar had just told them.
///
/// These tests drive the list from outside, the way the database does, so the
/// fix cannot be "re-read on open" again.
class _ControllableOrderRepository extends OrderTrackingRepository {
  _ControllableOrderRepository(this.updates);

  final StreamController<List<OrderSummary>> updates;

  @override
  Stream<List<OrderSummary>> watchMyOrders() => updates.stream;
}

OrderSummary summaryWithStatus(String orderId, String status) {
  return OrderSummary(
    orderId: orderId,
    billNumber: 'MP-ABT-00042',
    status: status,
    orderType: 'delivery',
    subtotal: 2450,
    tax: 196,
    deliveryCharges: 150,
    discountAmount: 300,
    total: 2496,
    createdAt: DateTime(2026, 9, 29, 14, 15),
    branchName: 'Mr. Pizza - Abbottabad',
    itemSummary: '2x Chicken Tikka Supreme',
    itemCount: 2,
    riderName: 'alyan',
  );
}

void main() {
  const orderId = '11111111-1111-1111-1111-111111111111';

  Future<StreamController<List<OrderSummary>>> pumpMyOrders(
    WidgetTester tester, {
    Size surface = const Size(430, 900),
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final updates = StreamController<List<OrderSummary>>();
    addTearDown(updates.close);

    final container = ProviderContainer(
      overrides: [
        orderTrackingRepositoryProvider
            .overrideWithValue(_ControllableOrderRepository(updates)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const MyOrdersScreen(),
        ),
      ),
    );
    return updates;
  }

  testWidgets('a cancelled order is shown as cancelled', (tester) async {
    final updates = await pumpMyOrders(tester);
    updates.add([summaryWithStatus(orderId, 'cancelled')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Cancelled'), findsOneWidget);
  });

  testWidgets('a status change arrives without the customer re-opening',
      (tester) async {
    // The regression. The order starts out genuinely in the kitchen.
    final updates = await pumpMyOrders(tester);
    updates.add([summaryWithStatus(orderId, 'in_kitchen')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Preparing in the kitchen'), findsOneWidget);
    expect(find.text('IN PROGRESS'), findsOneWidget);

    // The branch cancels it while the customer is still looking at the list.
    updates.add([summaryWithStatus(orderId, 'cancelled')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Same screen, no refresh, no pull-to-refresh.
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Preparing in the kitchen'), findsNothing);

    // And the row stops advertising itself as trackable, because a cancelled
    // order is no longer in flight. A card that still said "In progress" over a
    // cancelled order would be the same lie one field over.
    expect(find.text('IN PROGRESS'), findsNothing);
    expect(find.text('View Order'), findsOneWidget);
    expect(find.text('Track Order'), findsNothing);
  });

  testWidgets('the order keeps its bill number across a status change',
      (tester) async {
    // Guards against a "fix" that rebuilt the row from scratch and lost the
    // identity of the order it was describing.
    final updates = await pumpMyOrders(tester);
    updates.add([summaryWithStatus(orderId, 'out_for_delivery')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    updates.add([summaryWithStatus(orderId, 'delivered')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Delivered'), findsOneWidget);
    expect(find.text('MP-ABT-00042'), findsOneWidget);
    expect(find.text('2x Chicken Tikka Supreme'), findsOneWidget);
  });

  testWidgets('the longest status still fits a narrow phone', (tester) async {
    // Guards the header row, which used to overflow by over a hundred pixels
    // once the status was anything longer than "Delivered". The status is the
    // variable part of that row, so it has to be the thing tested against the
    // narrowest screen rather than the shortest label.
    final updates = await pumpMyOrders(
      tester,
      surface: const Size(360, 900),
    );
    updates.add([summaryWithStatus(orderId, 'ready_for_pickup')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ready for pickup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}