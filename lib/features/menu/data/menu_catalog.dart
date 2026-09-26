import '../models/menu_category.dart';
import '../models/menu_item.dart';

/// The menu as the database actually describes it: the real `categories` rows
/// plus every `menu_items` row placed under the category its `category_id`
/// points at.
class MenuCatalog {
  /// Real categories, ordered by `sort_order`.
  final List<MenuCategory> categories;

  /// Every item, whether or not its category could be resolved. Items are
  /// never dropped for having an unknown category — a missing heading must not
  /// make food disappear from the menu.
  final List<MenuItem> allItems;

  final Map<String, List<MenuItem>> _itemsByCategoryId;

  const MenuCatalog._({
    required this.categories,
    required this.allItems,
    required Map<String, List<MenuItem>> itemsByCategoryId,
  }) : _itemsByCategoryId = itemsByCategoryId;

  factory MenuCatalog.fromRows({
    required List<Map<String, dynamic>> itemRows,
    required List<Map<String, dynamic>> categoryRows,
  }) {
    final categories = categoryRows
        .map(MenuCategory.fromMap)
        .where((category) => category.isUsable)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final categoriesById = {for (final c in categories) c.id: c};

    final allItems = <MenuItem>[];
    final itemsByCategoryId = <String, List<MenuItem>>{};
    for (final category in categories) {
      itemsByCategoryId[category.id] = <MenuItem>[];
    }

    for (final row in itemRows) {
      final item = MenuItem.fromMap(row, categoriesById: categoriesById);
      if (item.id.isEmpty) continue;
      allItems.add(item);

      final categoryId = item.categoryId;
      if (categoryId == null) continue;
      // Keyed by the item's own category_id, so an item whose category row is
      // missing still files itself rather than landing in the wrong section.
      (itemsByCategoryId[categoryId] ??= <MenuItem>[]).add(item);
    }

    return MenuCatalog._(
      categories: categories,
      allItems: allItems,
      itemsByCategoryId: itemsByCategoryId,
    );
  }

  /// The items filed under [categoryId]. An id with no matching row returns an
  /// empty list rather than everything.
  List<MenuItem> itemsIn(String? categoryId) {
    if (categoryId == null) return const [];
    return _itemsByCategoryId[categoryId] ?? const [];
  }

  /// True when the catalog has nothing to show, so the UI can say so.
  bool get isEmpty => allItems.isEmpty;

  /// Total items across all sections, for "see all" style rows.
  int get itemCount => allItems.length;
}
