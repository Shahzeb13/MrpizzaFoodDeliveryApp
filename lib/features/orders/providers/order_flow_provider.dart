import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../menu/models/menu_item.dart';
import '../models/order.dart';

enum DemoOrderStatus {
  pending,
  assigned,
  accepted,
  pickedUp,
  completed,
  rejected,
}

class DemoOrder {
  final String id;
  final List<CartItem> items;
  final double subtotal;
  final double tax;
  final double deliveryFee;
  final double discount;
  final String? voucherCode;
  final double total;
  final OrderType orderType;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final String branchName;
  final DemoOrderStatus status;
  final String riderName;
  final String riderPhone;
  final double riderRating;
  final int pointsEarned;
  final DateTime createdAt;

  const DemoOrder({
    required this.id,
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.deliveryFee,
    this.discount = 0.0,
    this.voucherCode,
    required this.total,
    required this.orderType,
    required this.customerName,
    required this.customerPhone,
    required this.deliveryAddress,
    required this.branchName,
    this.status = DemoOrderStatus.pending,
    this.riderName = 'Test Rider',
    this.riderPhone = '+92 300 1234567',
    this.riderRating = 4.95,
    this.pointsEarned = 0,
    required this.createdAt,
  });

  String get itemsSummary {
    if (items.isEmpty) return 'Special Wood-Fired Pizza';
    return items.map((i) => '${i.quantity}x ${i.item.title}').join(', ');
  }

  DemoOrder copyWith({
    DemoOrderStatus? status,
    String? riderName,
    String? riderPhone,
    double? riderRating,
    int? pointsEarned,
  }) {
    return DemoOrder(
      id: id,
      items: items,
      subtotal: subtotal,
      tax: tax,
      deliveryFee: deliveryFee,
      discount: discount,
      voucherCode: voucherCode,
      total: total,
      orderType: orderType,
      customerName: customerName,
      customerPhone: customerPhone,
      deliveryAddress: deliveryAddress,
      branchName: branchName,
      status: status ?? this.status,
      riderName: riderName ?? this.riderName,
      riderPhone: riderPhone ?? this.riderPhone,
      riderRating: riderRating ?? this.riderRating,
      pointsEarned: pointsEarned ?? this.pointsEarned,
      createdAt: createdAt,
    );
  }
}

class LoyaltyPointsNotifier extends StateNotifier<int> {
  LoyaltyPointsNotifier() : super(120);

  void addPoints(int points) {
    state = state + points;
  }

  void deductPoints(int points) {
    state = (state - points).clamp(0, 999999);
  }
}

final loyaltyPointsProvider =
    StateNotifierProvider<LoyaltyPointsNotifier, int>((ref) {
  return LoyaltyPointsNotifier();
});

class OrderFlowNotifier extends StateNotifier<List<DemoOrder>> {
  final Ref ref;
  Timer? _reassignTimer;

  OrderFlowNotifier(this.ref) : super([]);

  @override
  void dispose() {
    _reassignTimer?.cancel();
    super.dispose();
  }

  DemoOrder? get activeOrder =>
      state.isEmpty ? null : state.first;

  /// Creates a new order on checkout.
  /// Automatically transitions from pending to assigned after 2.5s.
  DemoOrder createOrder({
    required List<CartItem> items,
    required double subtotal,
    required double tax,
    required double deliveryFee,
    required double discount,
    required String? voucherCode,
    required double total,
    required OrderType orderType,
    required String customerName,
    required String customerPhone,
    required String deliveryAddress,
    required String branchName,
  }) {
    final orderNumber = 9800 + state.length + 20;
    final order = DemoOrder(
      id: '#MP-$orderNumber',
      items: List.unmodifiable(items),
      subtotal: subtotal,
      tax: tax,
      deliveryFee: deliveryFee,
      discount: discount,
      voucherCode: voucherCode,
      total: total,
      orderType: orderType,
      customerName: customerName.isNotEmpty ? customerName : 'Aalyan Mughal',
      customerPhone: customerPhone.isNotEmpty ? customerPhone : '+92 331 6290108',
      deliveryAddress: deliveryAddress.isNotEmpty ? deliveryAddress : 'Mandian, Abbottabad',
      branchName: branchName.isNotEmpty ? branchName : 'Mr. Pizza – Abbottabad',
      status: DemoOrderStatus.pending,
      createdAt: DateTime.now(),
    );

    state = [order, ...state];

    // Simulated short delay: auto-assign to the newly created rider
    Future.delayed(const Duration(milliseconds: 2500), () {
      final current = state.firstWhere((o) => o.id == order.id, orElse: () => order);
      if (current.status == DemoOrderStatus.pending) {
        assignOrder(order.id, riderName: 'Test Rider', riderPhone: '+92 300 1234567');
      }
    });

    return order;
  }

  void assignOrder(String orderId, {String? riderName, String? riderPhone}) {
    state = state.map((o) {
      if (o.id == orderId) {
        return o.copyWith(
          status: DemoOrderStatus.assigned,
          riderName: riderName ?? 'Test Rider',
          riderPhone: riderPhone ?? '+92 300 1234567',
        );
      }
      return o;
    }).toList();
  }

  void acceptOrder(String orderId) {
    state = state.map((o) {
      if (o.id == orderId) {
        return o.copyWith(status: DemoOrderStatus.accepted);
      }
      return o;
    }).toList();
  }

  void rejectOrder(String orderId) {
    state = state.map((o) {
      if (o.id == orderId) {
        return o.copyWith(status: DemoOrderStatus.rejected);
      }
      return o;
    }).toList();

    // After a short simulated delay, automatically find and assign another rider
    _reassignTimer?.cancel();
    _reassignTimer = Timer(const Duration(milliseconds: 3000), () {
      state = state.map((o) {
        if (o.id == orderId && o.status == DemoOrderStatus.rejected) {
          return o.copyWith(
            status: DemoOrderStatus.assigned,
            riderName: 'Ali Hassan (Senior Rider)',
            riderPhone: '+92 331 9876543',
            riderRating: 4.98,
          );
        }
        return o;
      }).toList();
    });
  }

  void pickupOrder(String orderId) {
    state = state.map((o) {
      if (o.id == orderId) {
        return o.copyWith(status: DemoOrderStatus.pickedUp);
      }
      return o;
    }).toList();
  }

  int completeOrder(String orderId) {
    int earnedPoints = 0;
    state = state.map((o) {
      if (o.id == orderId) {
        // Loyalty calculation:
        // no voucher -> points = total * 10
        // voucher used -> points = discounted total * 10
        earnedPoints = (o.total * 10).round();
        ref.read(loyaltyPointsProvider.notifier).addPoints(earnedPoints);
        return o.copyWith(
          status: DemoOrderStatus.completed,
          pointsEarned: earnedPoints,
        );
      }
      return o;
    }).toList();
    return earnedPoints;
  }
}

final orderFlowProvider =
    StateNotifierProvider<OrderFlowNotifier, List<DemoOrder>>((ref) {
  return OrderFlowNotifier(ref);
});

final activeDemoOrderProvider = Provider<DemoOrder?>((ref) {
  final orders = ref.watch(orderFlowProvider);
  if (orders.isEmpty) return null;
  // Return the latest active or completed order
  return orders.first;
});
