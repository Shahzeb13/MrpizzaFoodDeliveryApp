import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/rider_repository.dart';
import '../models/rider_delivery.dart';

/// The rider's own record. Null means the panel has not created it yet, which
/// the dashboard shows as a setup message rather than an empty screen.
final riderDetailsProvider = FutureProvider<RiderDetails?>((ref) async {
  return ref.watch(riderRepositoryProvider).fetchRiderDetails();
});

/// The rider's assignments, re-read whenever the database says they changed.
final riderDeliveriesProvider = StreamProvider<List<RiderDelivery>>((ref) {
  return ref.watch(riderRepositoryProvider).streamDeliveries();
});

/// How many deliveries "My Deliveries" asks for at a time.
const int riderHistoryPageSize = 20;

/// What the "My Deliveries" screen has loaded so far.
class RiderHistoryState {
  final List<RiderDelivery> deliveries;
  final bool hasMore;
  final bool isLoadingMore;

  const RiderHistoryState({
    required this.deliveries,
    required this.hasMore,
    this.isLoadingMore = false,
  });

  RiderHistoryState copyWith({
    List<RiderDelivery>? deliveries,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return RiderHistoryState(
      deliveries: deliveries ?? this.deliveries,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

/// Loads "My Deliveries" one page at a time.
///
/// Separate from the dashboard's live stream on purpose: the dashboard only
/// ever needs the job in hand and a short recent peek, while this list can grow
/// to every delivery the rider has ever finished. Paging keeps both the
/// download and the rebuild small however long the rider has worked.
class RiderHistoryController extends AsyncNotifier<RiderHistoryState> {
  int _nextOffset = 0;

  @override
  Future<RiderHistoryState> build() => _loadFirstPage();

  Future<RiderHistoryState> _loadFirstPage() async {
    final page = await ref
        .read(riderRepositoryProvider)
        .fetchDeliveryHistoryPage(limit: riderHistoryPageSize, offset: 0);
    _nextOffset = page.deliveries.length;
    return RiderHistoryState(
      deliveries: page.deliveries,
      hasMore: page.hasMore,
    );
  }

  /// Re-reads the first page, throwing away anything already loaded.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_loadFirstPage);
  }

  /// Appends the next page, keeping what is already on screen.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await ref
          .read(riderRepositoryProvider)
          .fetchDeliveryHistoryPage(
              limit: riderHistoryPageSize, offset: _nextOffset);
      _nextOffset += page.deliveries.length;
      state = AsyncData(RiderHistoryState(
        deliveries: [...current.deliveries, ...page.deliveries],
        hasMore: page.hasMore,
      ));
    } catch (_) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
      rethrow;
    }
  }
}

final riderHistoryControllerProvider =
    AsyncNotifierProvider<RiderHistoryController, RiderHistoryState>(
        RiderHistoryController.new);

/// The lifecycle transitions. Each one invalidates the deliveries and the rider
/// record so the dashboard re-reads the truth from the database rather than
/// patching local state optimistically.
class RiderTransitionController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> claimOffer(String assignmentId) =>
      _run(() => ref.read(riderRepositoryProvider).claimOffer(assignmentId));

  Future<void> declineOffer(String assignmentId) =>
      _run(() => ref.read(riderRepositoryProvider).declineOffer(assignmentId));

  Future<void> markPickedUp(String assignmentId) =>
      _run(() => ref.read(riderRepositoryProvider).markPickedUp(assignmentId));

  Future<void> completeDelivery(String assignmentId) => _run(
      () => ref.read(riderRepositoryProvider).completeDelivery(assignmentId));

  Future<void> failDelivery(String assignmentId, String reason) => _run(() =>
      ref.read(riderRepositoryProvider).failDelivery(assignmentId, reason));

  /// Settles the cash once the delivery is done. The list is invalidated by
  /// [_run], so the job drops its "Cash Collected" button the moment this lands.
  Future<void> markCashCollected(String orderId) => _run(
      () => ref.read(riderRepositoryProvider).markCashCollected(orderId));

  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      ref.invalidate(riderDeliveriesProvider);
      ref.invalidate(riderDetailsProvider);
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
