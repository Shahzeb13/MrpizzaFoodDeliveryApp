import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/supabase_client.dart';
import '../models/rider_availability.dart';
import '../models/rider_delivery.dart';

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
        .select('branch_id, status, branch:branches(name, address)')
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
        .map((row) => RiderDelivery
            .fromAssignmentRow(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  /// The same assignments, re-read every time the database says they changed.
  ///
  /// Live only while the app is open. A rider with the app closed is not told
  /// about a new assignment until they next open it; push notifications are
  /// the fix for that and need a Firebase project.
  Stream<List<RiderDelivery>> streamDeliveries() {
    final riderId = client.auth.currentUser?.id;
    if (riderId == null) {
      return Stream<List<RiderDelivery>>.value(const <RiderDelivery>[]);
    }

    return Stream<List<RiderDelivery>>.multi((controller) {
      Future<void> emit() async {
        try {
          controller.add(await fetchDeliveries());
        } catch (error) {
          controller.addError(error);
        }
      }

      final channel = client
          .channel(riderAssignmentChannelName(riderId))
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'rider_assignments',
            filter: riderAssignmentChangeFilter(riderId),
            callback: (_) => emit(),
          );

      channel.subscribe();
      controller.onCancel = () => client.removeChannel(channel);

      emit();
    });
  }

  /// The store's configured payout per completed delivery, or 0 when it cannot
  /// be read. Zero is passed through to the earnings rule, which then reports
  /// 0 rather than inventing a figure.
  Future<double> fetchPayoutRate() async {
    final row = await client
        .from('store_settings')
        .select('rider_payout_per_delivery')
        .limit(1)
        .maybeSingle();
    if (row == null) return 0;
    final value = row['rider_payout_per_delivery'];
    if (value is num) return value.toDouble();
    return 0;
  }

  Future<void> claimOffer(String assignmentId) =>
      _callTransition('rider_claim_offer', {'p_assignment_id': assignmentId});

  Future<void> declineOffer(String assignmentId) => _callTransition(
      'rider_decline_offer', {'p_assignment_id': assignmentId});

  Future<void> markPickedUp(String assignmentId) => _callTransition(
      'rider_mark_picked_up', {'p_assignment_id': assignmentId});

  Future<void> completeDelivery(String assignmentId) => _callTransition(
      'rider_complete_delivery', {'p_assignment_id': assignmentId});

  Future<void> failDelivery(String assignmentId, String reason) =>
      _callTransition('rider_fail_delivery', {
        'p_assignment_id': assignmentId,
        'p_reason': reason,
      });

  Future<void> setAvailability(String status) =>
      _callTransition('rider_set_availability', {'p_status': status});

  Future<void> _callTransition(
    String function,
    Map<String, dynamic> params,
  ) async {
    try {
      await client.rpc(function, params: params);
    } on PostgrestException catch (error) {
      throw RiderRepositoryException(
        error.message.isEmpty
            ? 'That did not go through. Pull to refresh and try again.'
            : error.message,
      );
    }
  }
}

/// The rider's own record, used to tell "not set up yet" from "set up".
class RiderDetails {
  final String? branchId;
  final RiderAvailability availability;
  final String branchName;
  final String branchAddress;

  const RiderDetails({
    required this.branchId,
    required this.availability,
    required this.branchName,
    required this.branchAddress,
  });

  factory RiderDetails.fromMap(Map<String, dynamic> row) {
    final branch = row['branch'];
    final branchMap =
        branch is Map ? Map<String, dynamic>.from(branch) : <String, dynamic>{};
    return RiderDetails(
      branchId: row['branch_id'] as String?,
      availability: riderAvailabilityFromDatabaseValue(row['status'] as String?),
      branchName: (branchMap['name'] as String?) ?? '',
      branchAddress: (branchMap['address'] as String?) ?? '',
    );
  }
}

final riderRepositoryProvider = Provider<RiderRepository>(
  (ref) => RiderRepository(),
);
