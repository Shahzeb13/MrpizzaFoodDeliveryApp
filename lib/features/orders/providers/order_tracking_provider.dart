import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/order_tracking_repository.dart';
import '../models/order_tracking.dart';

final orderTrackingRepositoryProvider = Provider<OrderTrackingRepository>(
  (ref) => OrderTrackingRepository(),
);

/// The order checkout just created, held in memory so tracking can open straight
/// away. The previous version of this was an in-memory list of invented orders,
/// so the tracking screen had a "current order" with no row behind it.
final trackedOrderIdProvider = StateProvider<String?>((ref) => null);

/// The order the tracking screen should actually follow.
///
/// Checkout sets [trackedOrderIdProvider] explicitly. When it is empty — the app
/// was restarted, or the customer opened tracking from the drawer rather than
/// straight after paying — the newest order that has not finished yet is used
/// instead, so the screen is never blank while a real order is in flight. That
/// matters because the order is normally moved along by a branch dashboard on
/// another machine: the customer restarts the app, the branch changes the
/// status, and the screen has to still be watching the right row.
final orderIdToTrackProvider = FutureProvider.autoDispose<String?>((ref) async {
  final explicit = ref.watch(trackedOrderIdProvider);
  if (explicit != null && explicit.isNotEmpty) return explicit;

  final orders = await ref.watch(myOrdersProvider.future);
  for (final order in orders) {
    if (order.isStillMoving) return order.orderId;
  }

  // Nothing in flight — the newest order is still the one worth showing.
  return orders.isEmpty ? null : orders.first.orderId;
});

/// Live state of the order currently being tracked.
///
/// Null only when the customer genuinely has no order at all. A read that fails
/// comes back as an [OrderTrackingException] rather than as a placeholder order.
final activeOrderTrackingProvider =
    StreamProvider.autoDispose<OrderTracking?>((ref) async* {
  // The order checkout just placed is followed straight away, with no extra
  // round-trip to look it up first. Chaining the fallback lookup in front of
  // this is what made the screen sit on a spinner after every purchase.
  final explicit = ref.watch(trackedOrderIdProvider);
  if (explicit != null && explicit.isNotEmpty) {
    yield* ref
        .watch(orderTrackingRepositoryProvider)
        .watchOrderTracking(explicit);
    return;
  }

  final fallback = await ref.watch(orderIdToTrackProvider.future);
  if (fallback == null || fallback.isEmpty) {
    yield null;
    return;
  }

  yield* ref.watch(orderTrackingRepositoryProvider).watchOrderTracking(fallback);
});

/// One order fetched on demand, for opening a past order from the list.
final orderTrackingByIdProvider =
    FutureProvider.autoDispose.family<OrderTracking?, String>((ref, orderId) {
  return ref.watch(orderTrackingRepositoryProvider).fetchOrderTracking(orderId);
});

/// The signed-in customer's real orders. No demo rows, no bundled fallback.
///
/// A stream, not a one-shot read, so the list cannot disagree with the home bar
/// about the same order. As a `FutureProvider` this fetched once on open and
/// then sat on that snapshot: the bar followed an order in realtime and reported
/// it cancelled while this list kept claiming it was being prepared, until the
/// customer happened to pull to refresh. Every screen showing an order status
/// has to read from the same live source or they will drift apart.
final myOrdersProvider = StreamProvider.autoDispose<List<OrderSummary>>((ref) {
  return ref.watch(orderTrackingRepositoryProvider).watchMyOrders();
});
