import '../models/rider_delivery.dart';

/// The six database transitions a rider can trigger.
enum RiderAction { accept, decline, markPickedUp, complete, fail }

/// The label and action for the dashboard's one big button.
class RiderActionButton {
  final String label;
  final RiderAction action;

  const RiderActionButton({required this.label, required this.action});
}

/// The single next step for the active job, or null when there is nothing to do
/// yet (an unaccepted offer) or nothing left to do (finished).
///
/// Kept free of Flutter and Supabase so the lifecycle can be tested directly.
RiderActionButton? primaryActionFor(RiderDelivery delivery) {
  switch (delivery.assignmentStatus) {
    case 'accepted':
      return const RiderActionButton(
          label: "I've Picked Up", action: RiderAction.markPickedUp);
    case 'picked_up':
      return const RiderActionButton(
          label: 'Mark Delivered', action: RiderAction.complete);
    default:
      return null;
  }
}

/// Jobs waiting for this rider to accept or decline.
List<RiderDelivery> pendingOffersFor(List<RiderDelivery> deliveries) =>
    deliveries.where((d) => d.isOffer).toList();

/// The job this rider is doing, if any.
///
/// Returns a single job because the database enforces at most one active
/// assignment per rider: `rider_assignments_one_active_per_rider` in migration
/// `20260928093000_rider_one_active_assignment.sql` is a partial unique index
/// that refuses a second `accepted` or `picked_up` row for the same rider. The
/// first match is therefore always the only match.
RiderDelivery? activeDeliveryFor(List<RiderDelivery> deliveries) {
  for (final delivery in deliveries) {
    if (delivery.isActive) return delivery;
  }
  return null;
}

/// Everything that has ended, newest first.
List<RiderDelivery> deliveredHistoryFor(List<RiderDelivery> deliveries) {
  final history = deliveries.where((d) => d.isHistory).toList()
    ..sort((a, b) {
      final aTime = a.deliveredAt ?? a.pickedUpAt ?? a.assignedAt;
      final bTime = b.deliveredAt ?? b.pickedUpAt ?? b.assignedAt;
      if (aTime == null || bTime == null) return 0;
      return bTime.compareTo(aTime);
    });
  return history;
}

/// Payout earned, using the store's configured rate per completed delivery.
///
/// A rate of zero means the rate could not be read; it must never be turned
/// into a nonzero figure by guessing.
double earningsFor(
  List<RiderDelivery> deliveries,
  double payoutPerDelivery,
) {
  if (payoutPerDelivery <= 0) return 0;
  return completedCountFor(deliveries) * payoutPerDelivery;
}

/// How many deliveries this rider has completed.
int completedCountFor(List<RiderDelivery> deliveries) =>
    deliveries.where((d) => d.assignmentStatus == 'delivered').length;
