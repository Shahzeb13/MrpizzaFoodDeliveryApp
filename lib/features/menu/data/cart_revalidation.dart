import '../models/menu_item.dart';

/// What the checkout-time revalidation decided, ready for the cart to adopt.
class CartRevalidationResult {
  /// The full replacement line list: dropped lines are gone, kept lines carry
  /// the fresh menu item.
  final List<CartItem> adjustedItems;

  /// How many lines are no longer for sale and were dropped.
  final int removedCount;

  /// How many lines kept their item but at a new price.
  final int repricedCount;

  const CartRevalidationResult({
    required this.adjustedItems,
    required this.removedCount,
    required this.repricedCount,
  });

  bool get hasChanges => removedCount > 0 || repricedCount > 0;
}

/// Checks the cart lines against what is actually on sale and rebuilds them
/// accordingly.
///
/// A saved cart rides across days in the phone's storage, so by the time the
/// customer reaches checkout the kitchen may have repriced an item or taken it
/// off the menu. Revalidation answers both: unavailable items are removed (a
/// line can never be ordered if the item row is gone or `is_available` is
/// false — the read-only access rules hide those rows), and kept lines are
/// rebuilt around the current database row so the visible total uses today's
/// price, never the price a shopper saw last week.
///
/// Everything else about a line — size, crust, toppings, quantity and
/// instructions — is customer data and is never touched. [items] whose `id` is
/// missing from [availableItems] are removed; empty [availableItems] is not an
/// error, it is a fully unavailable menu.
CartRevalidationResult revalidateCartAgainstMenu({
  required List<CartItem> items,
  required Map<String, MenuItem> availableItems,
}) {
  final kept = <CartItem>[];
  var removed = 0;
  var repriced = 0;

  for (final line in items) {
    final liveItem = availableItems[line.item.id];
    if (liveItem == null) {
      removed++;
      continue;
    }

    final rebuilt = line.withMenuItem(liveItem);
    // One paisa of difference is a change worth telling the customer about;
    // but only for real moves, not floating-point dust.
    if ((line.unitPrice - rebuilt.unitPrice).abs() >= 0.01) {
      repriced++;
    }
    kept.add(rebuilt);
  }

  return CartRevalidationResult(
    adjustedItems: kept,
    removedCount: removed,
    repricedCount: repriced,
  );
}

/// The single sentence the checkout screen shows when the menu moved under a
/// saved cart. Null means nothing changed.
String? cartRevalidationMessage(CartRevalidationResult result) {
  if (!result.hasChanges) return null;
  if (result.removedCount > 0 && result.repricedCount > 0) {
    return 'The menu changed: some items were removed and others were repriced.';
  }
  if (result.removedCount > 0) {
    return '${result.removedCount == 1 ? 'An item is' : 'Some items are'} '
        'no longer available and were removed.';
  }
  return 'Prices were updated to today’s menu.';
}
