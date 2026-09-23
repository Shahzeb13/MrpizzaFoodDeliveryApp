import '../../../core/network/supabase_client.dart';
import '../models/branch.dart';
import '../models/order.dart';

class OrdersRepository {
  Future<List<Branch>> fetchBranches() async {
    try {
      final res = await supabase.from('branches').select();
      final branches = (res as List)
          .map((row) => Branch.fromMap(row as Map<String, dynamic>))
          .toList();
      if (branches.isEmpty) return mockBranches;
      branches.sort((a, b) => a.name.compareTo(b.name));
      return branches;
    } catch (_) {
      return mockBranches;
    }
  }

  /// Bundled branches used when the `branches` table is empty or unreachable,
  /// so checkout always has a selection to offer (mirrors the menu fallback).
  static const List<Branch> mockBranches = [
    Branch(
      id: 'branch_abbottabad',
      name: 'Mr. Pizza – Abbottabad',
      latitude: 34.1688,
      longitude: 73.2215,
    ),
    Branch(
      id: 'branch_mansehra',
      name: 'Mr. Pizza – Mansehra',
      latitude: 34.3302,
      longitude: 73.1969,
    ),
  ];

  /// Inserts the order header plus one `order_items` row per cart line.
  Future<void> placeOrder(Order order) async {
    final orderRes = await supabase
        .from('orders')
        .insert(order.toInsertMap())
        .select('id')
        .single();
    final orderId = orderRes['id'] as String;

    if (order.items.isNotEmpty) {
      await supabase
          .from('order_items')
          .insert(order.items.map((item) => item.toInsertMap(orderId)).toList());
    }
  }
}