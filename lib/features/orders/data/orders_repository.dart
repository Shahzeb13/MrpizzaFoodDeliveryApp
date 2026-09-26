import '../../../core/network/supabase_client.dart';
import '../models/branch.dart';
import '../models/order.dart';

/// The branches the app can offer, plus whether they are real database rows or
/// the bundled offline stand-ins.
///
/// The bundled branches do not have real `branches.id` UUIDs, so an order built
/// on them would fail the `orders.branch_id` foreign key. Callers must check
/// [usedFallbackData] and tell the user, instead of pretending the data is live.
class BranchCatalog {
  final List<Branch> branches;

  /// True when [branches] came from [OrdersRepository.bundledBranches] rather
  /// than from the `branches` table.
  final bool usedFallbackData;

  const BranchCatalog({required this.branches, required this.usedFallbackData});

  factory BranchCatalog.bundledFallback() => const BranchCatalog(
        branches: OrdersRepository.bundledBranches,
        usedFallbackData: true,
      );
}

class OrdersRepository {
  Future<BranchCatalog> fetchBranches() async {
    try {
      final res = await supabase.from('branches').select();
      return buildBranchCatalogFromRows(
        (res as List).cast<Map<String, dynamic>>(),
      );
    } catch (_) {
      return BranchCatalog.bundledFallback();
    }
  }

  /// Bundled branches used when the `branches` table is empty or unreachable,
  /// so checkout always has something to offer (mirrors the menu fallback).
  static const List<Branch> bundledBranches = [
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

  /// Turns raw `branches` rows into a [BranchCatalog], falling back to the
  /// bundled branches when the table has no rows.
  static BranchCatalog buildBranchCatalogFromRows(
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.isEmpty) return BranchCatalog.bundledFallback();
    final branches = rows.map(Branch.fromMap).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return BranchCatalog(branches: branches, usedFallbackData: false);
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