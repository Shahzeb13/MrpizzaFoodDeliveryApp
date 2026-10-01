import 'dart:async';
import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/supabase_client.dart';
import '../models/order_tracking.dart';
import 'coalesced_read_gate.dart';

/// Installed once per process. `RealtimeClient.onError`/`onClose`/`onOpen` are
/// setters that REPLACE the previous callback, so installing them per channel
/// would mean only the most recent channel reported anything.
bool _socketDiagnosticsInstalled = false;

/// Makes the realtime socket report on itself.
///
/// `subscribe()` returns the channel and every failure callback on the channel
/// itself is `@internal`. The socket, however, publishes errors, closes and
/// opens — so those are what gets watched here.
///
/// This exists because the failure mode is invisible by construction. A channel
/// that never joins, or a socket that is refused, produces no exception
/// anywhere; the safety-net poll then quietly keeps the screen correct, so the
/// only symptom is that updates feel twenty seconds late and nobody can say why.
/// With this installed, `flutter logs` either shows events arriving or shows the
/// socket refusing — which is the difference between a two-minute diagnosis and
/// an open-ended one.
void _installSocketDiagnostics(SupabaseClient client) {
  if (_socketDiagnosticsInstalled) return;
  _socketDiagnosticsInstalled = true;

  final realtime = client.realtime;

  realtime.onError((Object? error) {
    developer.log(
      'Realtime socket error. Order status will still be correct via the '
      'safety-net poll, but updates will be late.',
      name: 'mrpizza.realtime',
      level: 900,
      error: error,
    );
  });

  realtime.onClose((dynamic reason) {
    developer.log(
      'Realtime socket closed. Reason: $reason',
      name: 'mrpizza.realtime',
      level: 900,
    );
  });

  realtime.onOpen(() {
    developer.log(
      'Realtime socket open.',
      name: 'mrpizza.realtime',
    );
  });
}

/// Logs each realtime event, which is the positive proof that the fast path is
/// alive. Status changes are infrequent enough that this is not noise, and its
/// absence is the signal that matters.
void _reportRealtimeEvent(String label) {
  developer.log(
    'Realtime event on "$label" — re-reading from the database.',
    name: 'mrpizza.realtime',
  );
}

/// How often the tracking screen re-reads its order even when realtime says
/// nothing changed.
///
/// The order is usually moved along by a branch dashboard running on another
/// machine, so the app is a pure subscriber here. Realtime is instant when the
/// socket is healthy, but a phone that was backgrounded, asleep or briefly out
/// of coverage can miss an event outright — and a customer staring at "Preparing"
/// while their food is already at the door is the worst thing this screen can
/// do. This is the backstop for that, not the primary path.
const Duration _safetyNetRefreshInterval = Duration(seconds: 20);

/// How long a single read may take before it is treated as failed.
///
/// A hung request is worse than a failed one: without a bound, the tracking
/// screen waits on a spinner forever and the customer is stuck on a dead screen
/// with no way back. Bounded reads fail into the retry path instead.
const Duration _orderReadTimeout = Duration(seconds: 12);

/// A read the customer was not allowed to make, carrying the database's wording.
class OrderTrackingException implements Exception {
  final String message;

  const OrderTrackingException(this.message);

  @override
  String toString() => message;
}

/// Everything the customer's tracking and order-history screens read.
///
/// There is no local cache and no fallback data here on purpose. The old
/// tracking screen used to fall back to a `DemoOrder` whenever the real data
/// was missing, which is why an order that had just been placed still showed a
/// rider named "Test Rider" and a kitchen headline. A read that fails now
/// surfaces as a failure instead of as a convincing lie.
class OrderTrackingRepository {
  /// Resolved lazily, so a test can construct this without the global Supabase
  /// client having been initialised.
  final SupabaseClient? _injectedClient;

  OrderTrackingRepository({SupabaseClient? client}) : _injectedClient = client;

  SupabaseClient get client => _injectedClient ?? supabase;

  /// The live state of [orderId], or null when the database will not say.
  ///
  /// Bounded by [_orderReadTimeout]. An unbounded await here is what used to
  /// strand the customer: a request that never came back left the tracking
  /// screen spinning with no error, no retry and no way off the screen.
  Future<OrderTracking?> fetchOrderTracking(String orderId) async {
    if (orderId.isEmpty) return null;

    final result = await client
        .rpc(
          'order_tracking',
          params: {'p_order_id': orderId},
        )
        .timeout(_orderReadTimeout);

    final payload = _unwrapObject(result);
    if (payload == null) {
      throw const OrderTrackingException(
        'We could not read your order right now. Please try again.',
      );
    }
    if (payload['ok'] != true) {
      throw OrderTrackingException(
        _messageFrom(payload) ?? 'We could not find that order.',
      );
    }

    return OrderTracking.fromRpcResult(result);
  }

  /// The same tracking, refreshed whenever the database says it changed.
  ///
  /// Three tables carry the state a customer waits on: the branch moving their
  /// order through the kitchen (`orders`), the rider being assigned and picking
  /// up (`rider_assignments`), and the recorded status changes
  /// (`order_status_history`). Each event triggers a re-read rather than a
  /// locally patched value, so the screen can only ever show what the database
  /// says right now.
  ///
  /// Realtime is the fast path, not the only one. A backgrounded app, a dropped
  /// socket or a change made while the phone had no signal would otherwise
  /// leave a customer staring at a stale status with no way to tell, so a slow
  /// re-read runs alongside it. The interval is long enough to be free and short
  /// enough that nobody is misled about where their food is.
  ///
  /// Live only while the app is open. A customer with the app closed sees the
  /// current state the next time they open it; push notifications would be the
  /// fix for that and need a Firebase project.
  ///
  /// [channelPrefix] must differ whenever two screens follow the SAME order at
  /// once. The tracking screen and the persistent home/menu bar both watch an
  /// in-flight order, and realtime_client treats the channel name as a socket
  /// topic: two subscriptions on one topic fight over the same join reference
  /// and one of them silently stops receiving events. A distinct prefix keeps
  /// them on separate topics.
  Stream<OrderTracking?> watchOrderTracking(
    String orderId, {
    String channelPrefix = 'order-tracking',
  }) {
    if (orderId.isEmpty) {
      return Stream<OrderTracking?>.value(null);
    }

    return Stream<OrderTracking?>.multi((controller) {
      var closed = false;
      var hasDeliveredOnce = false;
      final gate = CoalescedReadGate();

      // What the customer is currently being shown. Used to stop a late or
      // out-of-order answer from walking the status backwards.
      OrderTracking? applied;

      Future<void> emit() => gate.request(() async {
        try {
          final tracking = await fetchOrderTracking(orderId);
          // The stream can be cancelled while the read is in flight — pulling
          // to refresh does exactly that — and adding to a closed controller
          // would throw out of a socket callback with nobody to catch it.
          if (closed || controller.isClosed) return;
          hasDeliveredOnce = true;

          // Belt and braces on top of the gate. The gate stops two reads racing;
          // this stops a single read that observed something older than what we
          // already showed, which a stale RPC result or a history row that
          // landed after the status update can still produce.
          if (applied != null &&
              tracking != null &&
              isOrderStageRegression(applied!.stage, tracking.stage)) {
            return;
          }

          applied = tracking;
          controller.add(tracking);
        } catch (error) {
          if (closed || controller.isClosed) return;
          // Only a failed FIRST read is something the customer has to act on.
          // After that, keep showing the last state the database actually gave
          // us and try again on the next tick — blanking a delivery screen
          // because one poll timed out is worse than showing data a few
          // seconds old.
          if (!hasDeliveredOnce) controller.addError(error);
        }
      });

      final channelLabel = '$channelPrefix-$orderId';
      final channel = client
          .channel(channelLabel)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: orderId,
            ),
            callback: (_) {
            _reportRealtimeEvent(channelLabel);
            emit();
          },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'order_status_history',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'order_id',
              value: orderId,
            ),
            callback: (_) {
            _reportRealtimeEvent(channelLabel);
            emit();
          },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'rider_assignments',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'order_id',
              value: orderId,
            ),
            callback: (_) {
            _reportRealtimeEvent(channelLabel);
            emit();
          },
          );

      final safetyNet = Timer.periodic(
        _safetyNetRefreshInterval,
        (_) => emit(),
      );

      _installSocketDiagnostics(client);
      channel.subscribe();
      controller.onCancel = () {
        closed = true;
        gate.close();
        safetyNet.cancel();
        client.removeChannel(channel);
      };

      emit();
    });
  }

  /// The signed-in customer's own orders, newest first.
  Future<List<OrderSummary>> fetchMyOrders() async {
    final result = await client.rpc('my_orders').timeout(_orderReadTimeout);
    final payload = _unwrapObject(result);

    if (payload == null) {
      throw const OrderTrackingException(
        'We could not load your orders right now. Please try again.',
      );
    }
    if (payload['ok'] != true) {
      throw OrderTrackingException(
        _messageFrom(payload) ?? 'We could not load your orders.',
      );
    }

    final rows = payload['orders'];
    if (rows is! List) return const [];

    return rows
        .whereType<Map>()
        .map((row) => OrderSummary.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  /// The signed-in customer's own orders, refreshed whenever one of them moves.
  ///
  /// This was a one-shot read, which is why My Orders and the home bar could
  /// contradict each other: the bar follows its order in realtime and said
  /// "Cancelled" while the list still showed whatever the status had been when
  /// the list was fetched. Two screens, one database, two different truths — and
  /// the stale one is the one a customer opens to check.
  ///
  /// Scoped to `customer_id` rather than left broad, so a re-read cannot be
  /// triggered by somebody else's order and each customer's list only ever
  /// reacts to their own rows. `orders` alone is enough: the list renders
  /// `orders.status`, and `order_status_history` is a log of the same changes
  /// rather than a separate source of truth.
  ///
  /// Realtime is still the fast path and not the only one, for the same reason
  /// as the tracking screen: a backgrounded app or a dropped socket can miss an
  /// event outright, and a stale status on an order the customer is looking at
  /// is exactly what they will not forgive.
  Stream<List<OrderSummary>> watchMyOrders() {
    final customerId = client.auth.currentUser?.id;
    // No signed-in customer means no orders to watch. Returning an empty stream
    // rather than subscribing to everything keeps an unauthenticated session
    // from pulling the whole `orders` table's worth of events.
    if (customerId == null || customerId.isEmpty) {
      return Stream<List<OrderSummary>>.value(const []);
    }

    return Stream<List<OrderSummary>>.multi((controller) {
      var closed = false;
      var hasDeliveredOnce = false;
      final gate = CoalescedReadGate();

      Future<void> emit() => gate.request(() async {
        try {
          final orders = await fetchMyOrders();
          if (closed || controller.isClosed) return;
          hasDeliveredOnce = true;
          controller.add(orders);
        } catch (error) {
          if (closed || controller.isClosed) return;
          // Same rule as the tracking stream: only a failed FIRST read is the
          // customer's problem. After that, keep the last list the database
          // actually gave us rather than emptying their order history because
          // one poll timed out.
          if (!hasDeliveredOnce) controller.addError(error);
        }
      });

      final channelLabel = 'my-orders-$customerId';
      final channel = client
          .channel(channelLabel)
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'customer_id',
              value: customerId,
            ),
            callback: (_) {
            _reportRealtimeEvent(channelLabel);
            emit();
          },
          );

      final safetyNet = Timer.periodic(
        _safetyNetRefreshInterval,
        (_) => emit(),
      );

      _installSocketDiagnostics(client);
      channel.subscribe();
      controller.onCancel = () {
        closed = true;
        gate.close();
        safetyNet.cancel();
        client.removeChannel(channel);
      };

      emit();
    });
  }

  static Map<String, dynamic>? _unwrapObject(Object? result) {
    if (result is Map) return Map<String, dynamic>.from(result);
    if (result is List && result.isNotEmpty && result.first is Map) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    return null;
  }

  static String? _messageFrom(Map<String, dynamic> payload) {
    final message = payload['message']?.toString().trim() ?? '';
    return message.isEmpty ? null : message;
  }
}
