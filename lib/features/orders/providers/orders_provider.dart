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

  const CheckoutState({
    this.orderType = OrderType.delivery,
    this.address,
    this.branch,
    this.branchIsNearest = false,
  });

  bool get isDelivery => orderType == OrderType.delivery;

  CheckoutState copyWith({
    OrderType? orderType,
    UserAddress? address,
    bool clearAddress = false,
    Branch? branch,
    bool? branchIsNearest,
  }) {
    return CheckoutState(
      orderType: orderType ?? this.orderType,
      address: clearAddress ? null : (address ?? this.address),
      branch: branch ?? this.branch,
      branchIsNearest: branchIsNearest ?? this.branchIsNearest,
    );
  }
}

class CheckoutNotifier extends StateNotifier<CheckoutState> {
  CheckoutNotifier() : super(const CheckoutState());

  /// Delivery: auto-selects the customer's default address (falling back to
  /// the first saved one) and, when that address has coordinates, the branch
  /// with the smallest straight-line distance to it.
  void selectDeliveryDefault({
    required List<UserAddress> addresses,
    required List<Branch> branches,
  }) {
    if (addresses.isEmpty) {
      state = CheckoutState(
        orderType: OrderType.delivery,
        branch: branches.firstOrNull,
      );
      return;
    }
    final defaultAddress = addresses.any((a) => a.isDefault)
        ? addresses.firstWhere((a) => a.isDefault)
        : addresses.first;
    final selection =
        BranchSelection.selectNearestBranch(defaultAddress, branches);
    state = CheckoutState(
      orderType: OrderType.delivery,
      address: defaultAddress,
      branch: selection.branch,
      branchIsNearest: selection.isNearestToAddress,
    );
  }

  /// Pickup: no address, simple branch pick-one.
  void selectPickup({required List<Branch> branches}) {
    state = CheckoutState(
      orderType: OrderType.pickup,
      address: null,
      branch: state.branch ?? branches.firstOrNull,
    );
  }

  /// Delivery with an explicitly chosen address (address picker).
  void selectAddress(UserAddress address, {required List<Branch> branches}) {
    final selection = BranchSelection.selectNearestBranch(address, branches);
    state = CheckoutState(
      orderType: OrderType.delivery,
      address: address,
      branch: selection.branch,
      branchIsNearest: selection.isNearestToAddress,
    );
  }

  void selectBranch(Branch branch) {
    // A hand-picked branch is never a verified "nearest" match.
    state = state.copyWith(branch: branch, branchIsNearest: false);
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