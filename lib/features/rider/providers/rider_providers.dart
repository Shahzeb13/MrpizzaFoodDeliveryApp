import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/rider_repository.dart';
import '../logic/delivery_actions.dart';
import '../models/rider_availability.dart';
import '../models/rider_delivery.dart';

/// The rider's own record. Null means the panel has not created it yet, which
/// the dashboard shows as a setup message rather than an empty screen.
final riderDetailsProvider = FutureProvider<RiderDetails?>((ref) async {
  return ref.watch(riderRepositoryProvider).fetchRiderDetails();
});

/// The rider's assignments, newest first.
final riderDeliveriesProvider = FutureProvider<List<RiderDelivery>>((ref) async {
  return ref.watch(riderRepositoryProvider).fetchDeliveries();
});

/// The store's payout per completed delivery. 0 means unreadable.
final payoutRateProvider = FutureProvider<double>((ref) async {
  return ref.watch(riderRepositoryProvider).fetchPayoutRate();
});

final riderAvailabilityProvider = FutureProvider<RiderAvailability>((ref) async {
  final details = await ref.watch(riderDetailsProvider.future);
  return details?.availability ?? RiderAvailability.offline;
});

/// Payout earned so far. Zero when the rate could not be read, never a guess.
final riderEarningsProvider = FutureProvider<double>((ref) async {
  final deliveries = await ref.watch(riderDeliveriesProvider.future);
  final rate = await ref.watch(payoutRateProvider.future);
  return earningsFor(deliveries, rate);
});

/// Going online and offline. The database refuses to mark a rider available
/// while they hold a job, and that refusal is rethrown so the dashboard can
/// show the database's own wording.
class RiderAvailabilityController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> goOnline() => _send('available');

  Future<void> goOffline() => _send('offline');

  Future<void> _send(String status) async {
    state = const AsyncLoading();
    try {
      await ref.read(riderRepositoryProvider).setAvailability(status);
      ref.invalidate(riderDetailsProvider);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

final riderAvailabilityController =
    NotifierProvider<RiderAvailabilityController, AsyncValue<void>>(
        RiderAvailabilityController.new);

/// The lifecycle transitions. Each one invalidates the deliveries and the rider
/// record so the dashboard re-reads the truth from the database rather than
/// patching local state optimistically.
class RiderTransitionController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> claimOffer(String assignmentId) =>
      _run(() => ref.read(riderRepositoryProvider).claimOffer(assignmentId));

  Future<void> declineOffer(String assignmentId) => _run(
      () => ref.read(riderRepositoryProvider).declineOffer(assignmentId));

  Future<void> markPickedUp(String assignmentId) => _run(
      () => ref.read(riderRepositoryProvider).markPickedUp(assignmentId));

  Future<void> completeDelivery(String assignmentId) => _run(
      () => ref.read(riderRepositoryProvider).completeDelivery(assignmentId));

  Future<void> failDelivery(String assignmentId, String reason) => _run(
      () => ref.read(riderRepositoryProvider).failDelivery(assignmentId, reason));

  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      ref.invalidate(riderDeliveriesProvider);
      ref.invalidate(riderDetailsProvider);
      ref.invalidate(riderEarningsProvider);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

final riderTransitionController =
    NotifierProvider<RiderTransitionController, AsyncValue<void>>(
        RiderTransitionController.new);
