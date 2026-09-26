import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../menu/models/menu_item.dart';
import '../../profile/models/profile.dart';
import '../data/orders_repository.dart';
import '../models/branch.dart';
import '../models/order.dart';
/// Snapshot of the most recently placed order, kept alive so the tracking
/// screen can display the real items even after the cart is cleared.
class LastOrderSnapshot {
  final List<CartItem> items;
  final OrderTotals totals;
  final OrderType orderType;

  const LastOrderSnapshot({
    required this.items,
    required this.totals,
    required this.orderType,
  });
}

final lastOrderSnapshotProvider =
    StateProvider<LastOrderSnapshot?>((ref) => null);

final ordersRepositoryProvider =
    Provider<OrdersRepository>((ref) => OrdersRepository());

/// The restaurant branches, loaded once and used for branch selection.
/// Wrapped in a [BranchCatalog] so the UI can tell real database rows apart
/// from the bundled offline fallback.
final branchesFutureProvider = FutureProvider<BranchCatalog>((ref) async {
  return ref.watch(ordersRepositoryProvider).fetchBranches();
});

/// Checkout selection state: delivery/pickup + chosen address & branch.
class CheckoutState {
  final OrderType orderType;
  final UserAddress? address;
  final Branch? branch;

  /// True only when [branch] was proven to be the closest branch to [address].
  /// The checkout screen must not call the branch "nearest" when this is false.
  final bool branchIsNearest;

  /// True when the customer picked [branch] by hand. A hand-picked branch is
  /// never overwritten by the automatic nearest-branch calculation, because
  /// the customer knows something the distance check does not.
  final bool branchWasChosenManually;

  const CheckoutState({
    this.orderType = OrderType.delivery,
    this.address,
    this.branch,
    this.branchIsNearest = false,
    this.branchWasChosenManually = false,
  });

  bool get isDelivery => orderType == OrderType.delivery;

  CheckoutState copyWith({
    OrderType? orderType,
    UserAddress? address,
    bool clearAddress = false,
    Branch? branch,
    bool? branchIsNearest,
    bool? branchWasChosenManually,
  }) {
    return CheckoutState(
      orderType: orderType ?? this.orderType,
      address: clearAddress ? null : (address ?? this.address),
      branch: branch ?? this.branch,
      branchIsNearest: branchIsNearest ?? this.branchIsNearest,
      branchWasChosenManually:
          branchWasChosenManually ?? this.branchWasChosenManually,
    );
  }
}

class CheckoutNotifier extends StateNotifier<CheckoutState> {
  CheckoutNotifier() : super(const CheckoutState());

  /// Delivery: auto-selects the customer's default address (falling back to
  /// the first saved one) and, when that address has coordinates, the branch
  /// with the smallest straight-line distance to it.
  ///
  /// An address with no coordinates leaves the current [CheckoutState.branch]
  /// alone instead of clearing it. A branch that was already worked out from
  /// the map pin is better than no branch, and clearing it here is what used to
  /// send the customer back to "Please select a branch first."
  void selectDeliveryDefault({
    required List<UserAddress> addresses,
    required List<Branch> branches,
  }) {
    if (addresses.isEmpty) {
      final existing = state.branch;
      state = CheckoutState(
        orderType: OrderType.delivery,
        branch: existing ?? branches.firstOrNull,
        branchIsNearest: existing != null && state.branchIsNearest,
        branchWasChosenManually:
            existing != null && state.branchWasChosenManually,
      );
      return;
    }
    final defaultAddress = addresses.any((a) => a.isDefault)
        ? addresses.firstWhere((a) => a.isDefault)
        : addresses.first;
    final selection =
        BranchSelection.selectNearestBranch(defaultAddress, branches);
    if (selection.branch != null) {
      state = CheckoutState(
        orderType: OrderType.delivery,
        address: defaultAddress,
        branch: selection.branch,
        branchIsNearest: selection.isNearestToAddress,
      );
      return;
    }
    state = state.copyWith(
      orderType: OrderType.delivery,
      address: defaultAddress,
    );
  }

  /// Pickup: no address, simple branch pick-one.
  void selectPickup({required List<Branch> branches}) {
    state = CheckoutState(
      orderType: OrderType.pickup,
      address: null,
      branch: state.branch ?? branches.firstOrNull,
      branchIsNearest: state.branch != null && state.branchIsNearest,
      branchWasChosenManually:
          state.branch != null && state.branchWasChosenManually,
    );
  }

  /// Delivery with an explicitly chosen address (address picker).
  void selectAddress(UserAddress address, {required List<Branch> branches}) {
    final selection = BranchSelection.selectNearestBranch(address, branches);
    if (selection.branch == null) {
      state = state.copyWith(
        orderType: OrderType.delivery,
        address: address,
      );
      return;
    }
    state = CheckoutState(
      orderType: OrderType.delivery,
      address: address,
      branch: selection.branch,
      branchIsNearest: selection.isNearestToAddress,
    );
  }

  /// Works out the closest branch from a live map pin.
  ///
  /// This is what makes the branch automatic: the customer chose a position on
  /// the home screen, and checkout turns that into a branch without needing a
  /// saved address row. A hand-picked branch is left untouched, and a pin-less
  /// call changes nothing rather than clearing a branch that is already good.
  void syncBranchFromPin({
    required double? latitude,
    required double? longitude,
    required List<Branch> branches,
  }) {
    if (state.branchWasChosenManually) return;
    if (latitude == null || longitude == null) return;

    final selection = BranchSelection.selectNearestBranchToPoint(
      latitude: latitude,
      longitude: longitude,
      branches: branches,
    );
    final branch = selection.branch;
    if (branch == null) return;

    state = state.copyWith(
      branch: branch,
      branchIsNearest: selection.isNearestToAddress,
      branchWasChosenManually: false,
    );
  }

  void selectBranch(Branch branch) {
    // A hand-picked branch is never a verified "nearest" match.
    state = state.copyWith(
      branch: branch,
      branchIsNearest: false,
      branchWasChosenManually: true,
    );
  }

  /// Uses [branch] because nothing better is known — no pin, no coordinates on
  /// the address, no coordinates on the branch rows.
  ///
  /// Unlike [selectBranch] this is not a customer decision, so it does not block
  /// a later pin from picking a better branch, and it makes no nearest claim.
  /// It exists so `orders.branch_id` (which is NOT NULL) can always be filled:
  /// an order is always routed somewhere, and the screen says plainly that the
  /// branch was not worked out from the customer's position.
  void selectBranchAutomatically(Branch branch) {
    if (state.branch?.id == branch.id) return;
    state = state.copyWith(
      branch: branch,
      branchIsNearest: false,
      branchWasChosenManually: false,
    );
  }

  /// Closer branch by straight-line distance, or null when the address has no
  /// coordinates yet. Prefer [BranchSelection.selectNearestBranch], which also
  /// reports whether the pick is genuinely the nearest one.
  static Branch? nearestBranch(UserAddress address, List<Branch> branches) {
    return BranchSelection.selectNearestBranch(address, branches).branch;
  }
}

final checkoutProvider =
    StateNotifierProvider<CheckoutNotifier, CheckoutState>((ref) {
  return CheckoutNotifier();
});