import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/supabase_client.dart';
import '../../notifications/services/push_notification_sender.dart';
import '../../orders/data/coalesced_read_gate.dart';

import '../models/rider_delivery.dart';

/// How often the rider panel re-reads its work even when nothing has been
/// pushed.
///
/// Same figure the customer order screens use.
const Duration riderSafetyNetPollInterval = Duration(seconds: 20);

/// How long the panel waits before retrying its very first read.
///
/// A read fired at the moment of login can fail once against a session that is
/// still settling. Without a quick retry the rider stares at a database error
/// until the 20-second safety-net poll lands, which made a one-off race look
/// like a broken dashboard.
const Duration riderFirstReadRetryDelay = Duration(seconds: 2);

/// How many attempts the first read gets before its failure is shown.
///
/// Four attempts, two seconds apart, covers a login race while still telling
/// the rider about a genuinely unreachable backend within about six seconds.
const int riderFirstReadMaxAttempts = 4;

/// A channel name unique to this rider, so two signed-in riders on the same
/// socket do not end up sharing a subscription.
String riderAssignmentChannelName(String riderId) =>
    'rider-assignments-$riderId';

/// Scopes the subscription to one rider's rows.
///
/// This is not an optimisation. Without the filter the client would ask for
/// every rider's assignments; RLS would still refuse to hand over rows the
/// caller cannot see, but the filter keeps the traffic honest and avoids
/// relying on a second line of defence for the one query a rider makes.
PostgresChangeFilter riderAssignmentChangeFilter(String riderId) {
  return PostgresChangeFilter(
    type: PostgresChangeFilterType.eq,
    column: 'rider_id',
    value: riderId,
  );
}

/// A transition the database refused, carrying the reason it gave.
class RiderRepositoryException implements Exception {
  final String message;

  const RiderRepositoryException(this.message);

  @override
  String toString() => message;
}

/// Everything the rider screen needs from the database.
///
/// This class issues no table writes. Every lifecycle change goes through a
/// database function, so the assignment, the order status and the history row
/// can never disagree, and a rejected transition arrives here as a
/// [RiderRepositoryException] carrying the database's own wording.
class RiderRepository {
  /// Resolved lazily on purpose. The global Supabase client throws when the SDK
  /// has not been initialised, so a test that subclasses this repository and
  /// overrides every method must not trigger it just by being constructed.
  final SupabaseClient? _injectedClient;

  /// The rider this repository acts as. Defaults to the signed-in session and is
  /// injectable so tests do not need a live session.
  final String? _explicitUserId;

  RiderRepository({SupabaseClient? client, String? signedInUserId})
      : _injectedClient = client,
        _explicitUserId = signedInUserId;

  /// The client to talk to: injected in tests, the global one in the app.
  SupabaseClient get client => _injectedClient ?? supabase;

  /// The id of the rider whose work this repository reads and changes.
  String? get signedInUserId => _explicitUserId ?? client.auth.currentUser?.id;

  /// The rider's own record, or null only when the dashboard has genuinely not
  /// created one yet.
  ///
  /// The read is filtered by this rider's id rather than relying on RLS to do
  /// it. Without the filter the query returns one row per rider in the system,
  /// `maybeSingle()` throws on the extra rows, and that error was being reported
  /// as "your account is not set up" — the wrong message for a rider who does
  /// have an account.
  Future<RiderDetails?> fetchRiderDetails() async {
    final riderId = signedInUserId;
    if (riderId == null) return null;

    final row = await client
        .from('rider_details')
        .select('branch_id, branch:branches(name, address)')
        .eq('profile_id', riderId)
        .maybeSingle();

    if (row == null) return null;
    return RiderDetails.fromMap(row);
  }

  /// The rider's assignments joined to the order contact snapshot and branch.
  Future<List<RiderDelivery>> fetchDeliveries() async {
    final rows = await client.rpc('rider_deliveries');
    if (rows is! List) return const [];
    return rows
        .map((row) => RiderDelivery.fromAssignmentRow(
            Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  /// One page of finished deliveries, newest first.
  ///
  /// Reads through the same `rider_deliveries` function as the dashboard, but
  /// asks the database for only [limit] rows from [offset] and for finished
  /// jobs only. A rider with years of history therefore downloads one screenful
  /// at a time instead of the whole list just to open "My Deliveries".
  ///
  /// One extra row is requested so [RiderDeliveryPage.hasMore] is known without
  /// a separate count or an empty page at the end of an exact multiple.
  Future<RiderDeliveryPage> fetchDeliveryHistoryPage({
    required int limit,
    required int offset,
  }) async {
    final rows = await client.rpc('rider_deliveries', params: {
      'p_limit': limit + 1,
      'p_offset': offset,
      'p_history_only': true,
    });
    if (rows is! List) {
      return const RiderDeliveryPage(deliveries: [], hasMore: false);
    }
    final deliveries = rows
        .map((row) => RiderDelivery.fromAssignmentRow(
            Map<String, dynamic>.from(row as Map)))
        .toList();
    final hasMore = deliveries.length > limit;
    return RiderDeliveryPage(
      deliveries: hasMore ? deliveries.take(limit).toList() : deliveries,
      hasMore: hasMore,
    );
  }

  /// The same assignments, re-read every time the database says they changed.
  ///
  /// Realtime is the fast path and a poll is the floor underneath it. Relying on
  /// the socket alone meant a rider who never thought to pull down saw no new
  /// order at all, which is the one failure a delivery panel cannot have: the
  /// work is sitting there waiting while the screen says there is nothing. The
  /// socket also never reports its own failures — a channel that failed to join,
  /// or died on a network change, is indistinguishable from an idle one — so a
  /// silent drop looks exactly like a quiet afternoon.
  ///
  /// Live only while the app is open. A rider with the app closed is not told
  /// about a new assignment until they next open it; push notifications are the
  /// fix for that and need a Firebase project.
  Stream<List<RiderDelivery>> streamDeliveries({
    Duration safetyNetPollInterval = riderSafetyNetPollInterval,
    Duration firstReadRetryDelay = riderFirstReadRetryDelay,
    int firstReadMaxAttempts = riderFirstReadMaxAttempts,
  }) {
    final riderId = signedInUserId;
    if (riderId == null) {
      return Stream<List<RiderDelivery>>.value(const <RiderDelivery>[]);
    }

    return Stream<List<RiderDelivery>>.multi((controller) {
      // Two doors into one room, so the reads are serialised. Without this, an
      // event landing as a tick fires can resolve second with older data and
      // rewind the list the rider is looking at.
      final readGate = CoalescedReadGate();
      Timer? safetyNet;
      Timer? retry;
      var closed = false;

      // The first read right after login can lose a race with the freshly
      // issued session: the request goes out before PostgREST accepts the new
      // token, fails once, and the rider is shown "Could not load your
      // deliveries" until the 20-second poll happens to succeed. Retrying the
      // first read quickly means a transient refusal costs a moment, not a
      // screen full of database error text.
      var firstReadAttempts = 0;

      // Set once a real list has been shown. After that a failed poll is a
      // transport hiccup, not a reason to replace the rider's work with an
      // error — the same rule the customer order streams follow.
      var hasDeliveredOnce = false;

      Future<void> emit() async {
        await readGate.request(() async {
          if (closed || controller.isClosed) return;
          try {
            final deliveries = await fetchDeliveries();
            if (closed || controller.isClosed) return;
            hasDeliveredOnce = true;
            firstReadAttempts = 0;
            controller.add(deliveries);
          } catch (error) {
            if (closed || controller.isClosed) return;

            // Keep showing the last work list the database actually gave us
            // rather than blanking the dashboard because one poll failed.
            if (hasDeliveredOnce) return;

            firstReadAttempts++;
            if (firstReadAttempts < firstReadMaxAttempts) {
              retry?.cancel();
              retry = Timer(firstReadRetryDelay, emit);
              return;
            }

            controller.addError(error);
          }
        });
      }

      // The socket is an optimisation, not a dependency. Opening it is allowed
      // to fail: if it throws, the poll below still runs, which is the entire
      // reason there is a poll. Letting this take the stream down with it would
      // leave a rider with a dead panel and no way to recover short of reopening
      // the app.
      RealtimeChannel? channel;
      try {
        channel = client
            .channel(riderAssignmentChannelName(riderId))
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'rider_assignments',
              filter: riderAssignmentChangeFilter(riderId),
              callback: (_) => emit(),
            );
        channel.subscribe();
      } catch (_) {
        channel = null;
      }

      safetyNet = Timer.periodic(safetyNetPollInterval, (_) => emit());

      controller.onCancel = () {
        closed = true;
        safetyNet?.cancel();
        retry?.cancel();
        readGate.close();
        final open = channel;
        if (open != null) client.removeChannel(open);
      };

      emit();
    });
  }

  Future<void> claimOffer(String assignmentId) =>
      _callTransition('rider_claim_offer', {'p_assignment_id': assignmentId});

  Future<void> declineOffer(String assignmentId) =>
      _callTransition('rider_decline_offer', {'p_assignment_id': assignmentId});

  Future<void> markPickedUp(String assignmentId) => _callTransition(
      'rider_mark_picked_up', {'p_assignment_id': assignmentId});

  Future<void> completeDelivery(String assignmentId) => _callTransition(
      'rider_complete_delivery', {'p_assignment_id': assignmentId});

  /// Reports that [assignmentId] could not be delivered, giving [reason].
  ///
  /// The report ends the order: the database moves it to `cancelled` — not
  /// back to the panel's reassignable state — so the branch sees a lost order
  /// instead of a dead one reviving as "new".
  Future<void> failDelivery(String assignmentId, String reason) =>
      _callTransition('rider_fail_delivery', {
        'p_assignment_id': assignmentId,
        'p_reason': reason,
      });

  /// Marks the cash for [orderId] as collected.
  ///
  /// Separate from [completeDelivery] on purpose: the delivery is finished when
  /// the pizza is handed over, but the money is not in the till until then, and
  /// an order the customer never paid for still has to be closeable out.
  Future<void> markCashCollected(String orderId) =>
      _callTransition('mark_cash_collected', {'p_order_id': orderId});

  Future<void> _callTransition(
    String function,
    Map<String, dynamic> params,
  ) async {
    try {
      await client.rpc(function, params: params);
      _notifyOnTransition(function, params);
    } on PostgrestException catch (error) {
      throw RiderRepositoryException(
        error.message.isEmpty
            ? 'That did not go through. Pull to refresh and try again.'
            : error.message,
      );
    }
  }

  void _notifyOnTransition(String function, Map<String, dynamic> params) {
    // The database announces a delivery the rider reported as failed itself:
    // the order lands on `cancelled` and the order-status trigger pushes the
    // customer a real "Order Cancelled". Sending this one too would arrive as
    // a second, vaguer notification for the same moment.
    if (function == 'rider_fail_delivery') return;

    // Fire and forget - don't block rider actions
    Future.microtask(() async {
      try {
        final assignmentId = params['p_assignment_id'] as String?;
        final orderId = params['p_order_id'] as String?;
        String? customerId;

        if (assignmentId != null) {
          final row = await client
              .from('rider_assignments')
              .select('order_id, orders(customer_id)')
              .eq('id', assignmentId)
              .maybeSingle();
          if (row != null) {
            final orders = row['orders'];
            if (orders is Map) {
              customerId = orders['customer_id'] as String?;
            }
            if (customerId == null && orderId == null) {
              orderIdFromRow(row);
            }
          }
        }

        if (orderId != null && customerId == null) {
          final row = await client
              .from('orders')
              .select('customer_id')
              .eq('id', orderId)
              .maybeSingle();
          customerId = row?['customer_id'] as String?;
        }

        if (customerId == null) return;

        String title = 'Order Update';
        String body = 'Your order status has been updated';

        if (function == 'rider_claim_offer') {
          title = 'Rider Assigned';
          body = 'A rider has been assigned to your order';
        } else if (function == 'rider_mark_picked_up') {
          title = 'Order Picked Up';
          body = 'Your order is on the way';
        } else if (function == 'rider_complete_delivery') {
          title = 'Order Delivered';
          body = 'Your order has been delivered. Enjoy!';
        }

        await PushNotificationSender.instance.sendToUser(
          userId: customerId,
          title: title,
          body: body,
          data: {'type': 'order_update', 'function': function},
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Push notification trigger error: $e');
        }
      }
    });
  }

  String? orderIdFromRow(Map<String, dynamic> row) => row['order_id'] as String?;
}

/// The rider's own record, used to tell "not set up yet" from "set up".
class RiderDetails {
  final String? branchId;
  final String branchName;
  final String branchAddress;

  const RiderDetails({
    required this.branchId,
    required this.branchName,
    required this.branchAddress,
  });

  factory RiderDetails.fromMap(Map<String, dynamic> row) {
    final branch = row['branch'];
    final branchMap =
        branch is Map ? Map<String, dynamic>.from(branch) : <String, dynamic>{};
    return RiderDetails(
      branchId: row['branch_id'] as String?,
      branchName: (branchMap['name'] as String?) ?? '',
      branchAddress: (branchMap['address'] as String?) ?? '',
    );
  }
}

/// One page of finished deliveries, and whether another page exists.
class RiderDeliveryPage {
  final List<RiderDelivery> deliveries;
  final bool hasMore;

  const RiderDeliveryPage({
    required this.deliveries,
    required this.hasMore,
  });
}

final riderRepositoryProvider = Provider<RiderRepository>(
  (ref) => RiderRepository(),
);
