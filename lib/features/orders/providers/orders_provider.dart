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

/// The two restaurant branches, loaded once and used for branch selection.
final branchesFutureProvider = FutureProvider<List<Branch>>((ref) async {
  return ref.watch(ordersRepositoryProvider).fetchBranches();
});

/// Checkout selection state: delivery/pickup + chosen address & branch.
class CheckoutState {
  final OrderType orderType;
  final UserAddress? address;
  final Branch? branch;

  const CheckoutState({
    this.orderType = OrderType.delivery,
    this.address,
    this.branch,
  });

  bool get isDelivery => orderType == OrderType.delivery;

  CheckoutState copyWith({
    OrderType? orderType,
    UserAddress? address,
    bool clearAddress = false,
    Branch? branch,
  }) {
    return CheckoutState(
      orderType: orderType ?? this.orderType,
      address: clearAddress ? null : (address ?? this.address),
      branch: branch ?? this.branch,
    );
  }
}

class CheckoutNotifier extends StateNotifier<CheckoutState> {
  CheckoutNotifier() : super(const CheckoutState());

  /// Delivery: auto-selects the customer's default address (falling back to
  /// the first saved one) and the closer branch via Haversine distance.
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
    state = CheckoutState(
      orderType: OrderType.delivery,
      address: defaultAddress,
      branch: nearestBranch(defaultAddress, branches),
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
    state = CheckoutState(
      orderType: OrderType.delivery,
      address: address,
      branch: nearestBranch(address, branches),
    );
  }

  void selectBranch(Branch branch) {
    state = state.copyWith(branch: branch);
  }

  /// Closer branch by straight-line distance. Addresses without coordinates
  /// fall back to the first branch.
  static Branch? nearestBranch(UserAddress address, List<Branch> branches) {
    if (branches.isEmpty) return null;
    final addressLat = address.latitude;
    final addressLng = address.longitude;
    if (addressLat == null || addressLng == null) return branches.first;

    Branch? nearest;
    var minDistance = double.infinity;
    for (final branch in branches) {
      final distance = branch.distanceTo(addressLat, addressLng);
      if (distance == null) continue;
      if (distance < minDistance) {
        minDistance = distance;
        nearest = branch;
      }
    }
    return nearest ?? branches.first;
  }
}

final checkoutProvider =
    StateNotifierProvider<CheckoutNotifier, CheckoutState>((ref) {
  return CheckoutNotifier();
});