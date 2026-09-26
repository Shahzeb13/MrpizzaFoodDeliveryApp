/// A row from the `categories` table.
///
/// The app used to invent its own eight-heading enum and read a `category`
/// column that `menu_items` does not have, so every item landed under one
/// heading. The real category now travels with the item as a [MenuCategory].
class MenuCategory {
  final String id;
  final String name;
  final int sortOrder;

  /// Sort order for a row that has none, so it ends up last instead of first.
  static const int unsortedSortOrder = 1 << 30;

  const MenuCategory({
    required this.id,
    required this.name,
    this.sortOrder = unsortedSortOrder,
  });

  factory MenuCategory.fromMap(Map<String, dynamic> map) {
    final rawOrder = map['sort_order'];
    return MenuCategory(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString().trim(),
      sortOrder: rawOrder is num
          ? rawOrder.toInt()
          : int.tryParse('$rawOrder') ?? unsortedSortOrder,
    );
  }

  /// Categories without a name cannot be shown on a tab, so they are dropped
  /// rather than rendered as a blank tab.
  bool get isUsable => id.isNotEmpty && name.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is MenuCategory && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'MenuCategory($name)';
}
