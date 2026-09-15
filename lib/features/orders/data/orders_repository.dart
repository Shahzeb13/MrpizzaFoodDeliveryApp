import '../../../core/network/supabase_client.dart';
import '../models/branch.dart';
import '../models/order.dart';

class OrdersRepository {
  Future<List<Branch>> fetchBranches() async {
    final res = await supabase.from('branches').select();
    final branches = (res as List)
        .map((row) => Branch.fromMap(row as Map<String, dynamic>))
        .toList();
    branches.sort((a, b) => a.name.compareTo(b.name));
    return branches;
  }

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