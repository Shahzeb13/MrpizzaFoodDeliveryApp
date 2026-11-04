import 'menu_category.dart';

enum PizzaSize {
  small('Small 8"', 1.0, 'Serves 1'),
  medium('Medium 10"', 1.35, 'Serves 2-3'),
  large('Large 12"', 1.70, 'Serves 3-4'),
  family('Family 14"', 2.10, 'Serves 4-6');

  final String name;
  final double priceMultiplier;
  final String description;
  const PizzaSize(this.name, this.priceMultiplier, this.description);
}

enum PizzaCrust {
  thin('Classic Thin Crust', 0.0),
  handTossed('Hand Tossed Italian', 0.0),
  stuffed('Garlic Butter Stuffed', 180.0),
  cheeseBurst('Double Cheese Burst', 250.0);

  final String name;
  final double extraPrice;
  const PizzaCrust(this.name, this.extraPrice);
}

enum BurgerPatty {
  crispyChicken('Crispy Fried Chicken', 0.0),
  doubleBeef('Juicy Double Beef Patty', 150.0),
  grilledChicken('Smokey Grilled Chicken', 50.0);

  final String name;
  final double extraPrice;
  const BurgerPatty(this.name, this.extraPrice);
}

class ToppingOption {
  final String name;
  final double price;
  final String icon;

  const ToppingOption({
    required this.name,
    required this.price,
    required this.icon,
  });
}

class MenuItem {
  final String id;
  final String title;
  final String description;
  final double basePrice;
  final double? originalPrice;
  final String imageUrl;

  /// The `menu_items.category_id` foreign key, or null when the row has none.
  final String? categoryId;

  /// The real category name from the `categories` table, empty when the row
  /// has no category or the category row could not be found. Never invented:
  /// a wrong heading is worse than an honest blank.
  final String categoryName;

  final double rating;
  final int reviewCount;
  final String prepTime;
  final int calories;
  final bool isVeg;
  final bool isSpicy;
  final bool isBestseller;
  final List<ToppingOption> availableToppings;

  const MenuItem({
    required this.id,
    required this.title,
    required this.description,
    required this.basePrice,
    this.originalPrice,
    required this.imageUrl,
    this.categoryId,
    this.categoryName = '',
    this.rating = 4.8,
    this.reviewCount = 120,
    this.prepTime = '15-20 min',
    this.calories = 450,
    this.isVeg = false,
    this.isSpicy = false,
    this.isBestseller = false,
    this.availableToppings = const [],
  });

  /// Builds a MenuItem from a Supabase `menu_items` row. Column spellings are
  /// resolved tolerantly (name/title, price/base_price, image_url/image, …) so
  /// the mapping keeps working as the table evolves.
  ///
  /// The category comes from `category_id`, never from a `category` column —
  /// that column does not exist, and reading it silently put all 88 items under
  /// one heading. [categoriesById] resolves the id to a name; when the row
  /// carries an embedded `categories` object that wins, so a single joined
  /// query is enough.
  factory MenuItem.fromMap(
    Map<String, dynamic> map, {
    Map<String, MenuCategory> categoriesById = const {},
  }) {
    final rawCategoryId = map['category_id'] ?? map['categoryId'];
    final categoryId = rawCategoryId?.toString();

    return MenuItem(
      id: _asString(map['id'] ?? map['menu_item_id']),
      title: _asString(map['title'] ?? map['name'], fallback: 'Unnamed item'),
      description: _asString(map['description'] ?? map['desc']),
      basePrice: _asDouble(map['base_price'] ?? map['price'] ?? 0),
      originalPrice: map['original_price'] == null
          ? null
          : _asDouble(map['original_price']),
      imageUrl: _asString(
        map['image_url'] ?? map['image'] ?? map['imageurl'],
      ),
      categoryId: (categoryId == null || categoryId.isEmpty)
          ? null
          : categoryId,
      categoryName: _resolveCategoryName(map, categoryId, categoriesById),
      rating: _asDouble(map['rating'] ?? 4.8),
      reviewCount: _asInt(map['review_count'] ?? map['reviews'] ?? 120),
      prepTime: _asString(map['prep_time'], fallback: '15-20 min'),
      calories: _asInt(map['calories'] ?? 450),
      isVeg: map['is_veg'] == true,
      isSpicy: map['is_spicy'] == true,
      isBestseller:
          map['is_bestseller'] == true || map['is_best_seller'] == true,
    );
  }

  /// Reads the category name from the embedded `categories` object when the
  /// query joined it, otherwise from the separately fetched category list.
  static String _resolveCategoryName(
    Map<String, dynamic> map,
    String? categoryId,
    Map<String, MenuCategory> categoriesById,
  ) {
    final embedded = map['categories'];
    if (embedded is Map<String, dynamic>) {
      final name = (embedded['name'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    }
    if (categoryId == null) return '';
    return categoriesById[categoryId]?.name ?? '';
  }
}

String _asString(Object? value, {String fallback = ''}) {
  final s = value?.toString().trim() ?? '';
  return s.isEmpty ? fallback : s;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// Reads back a persisted [PizzaSize]. The constant name is stored because it
/// survives a marketing wording change that would leave saved carts with a
/// size no current label matches.
PizzaSize? _pizzaSizeFromStored(String? stored) {
  final value = stored?.trim() ?? '';
  for (final candidate in PizzaSize.values) {
    if (value == candidate.toString() || value == candidate.name) {
      return candidate;
    }
  }
  return null;
}

/// Reads back a persisted [PizzaCrust]; same stability rule as the size.
PizzaCrust? _pizzaCrustFromStored(String? stored) {
  final value = stored?.trim() ?? '';
  for (final candidate in PizzaCrust.values) {
    if (value == candidate.toString() || value == candidate.name) {
      return candidate;
    }
  }
  return null;
}

class CartItem {
  final String id;
  final MenuItem item;
  final PizzaSize size;
  final PizzaCrust crust;
  final List<ToppingOption> selectedToppings;
  final int quantity;
  final String? specialInstructions;

  const CartItem({
    required this.id,
    required this.item,
    required this.size,
    required this.crust,
    required this.selectedToppings,
    this.quantity = 1,
    this.specialInstructions,
  });

  /// The line's identity: the same item, size, crust and topping set merged
  /// into one line. Both [CartNotifier.addItem] and restoring a saved cart go
  /// through this so a restored line still merges with the one the item sheet
  /// adds next.
  static String lineIdentity(
    String menuItemId,
    PizzaSize size,
    PizzaCrust crust,
    List<ToppingOption> toppings,
  ) {
    return '${menuItemId}_${size.name}_${crust.name}_${toppings.map((t) => t.name).join('_')}';
  }

  /// Cart-shaped storage record for session persistence. Only what the cart
  /// needs is kept: rebuilding the item's full detail from the database is the
  /// checkout-time revalidation's job, not storage's.
  Map<String, dynamic> toStorageMap() => {
        'item': {
          'id': item.id,
          'title': item.title,
          'description': item.description,
          'basePrice': item.basePrice,
          'originalPrice': item.originalPrice,
          'imageUrl': item.imageUrl,
          'categoryId': item.categoryId,
          'categoryName': item.categoryName,
          'isVeg': item.isVeg,
          'isSpicy': item.isSpicy,
        },
        'size': size.toString(),
        'crust': crust.toString(),
        'toppings': [
          for (final topping in selectedToppings)
            {
              'name': topping.name,
              'price': topping.price,
              'icon': topping.icon,
            },
        ],
        'quantity': quantity,
        'instructions': specialInstructions,
      };

  /// Rebuilds a line from storage, or null when the record is unreadable
  /// (renamed enum, corrupted JSON, …). A null simply leaves the line out;
  /// one bad line must not empty the whole saved cart.
  static CartItem? fromStorageMap(Map<String, dynamic> map) {
    try {
      final rawItem = map['item'];
      if (rawItem is! Map<String, dynamic>) return null;

      final sizeName = map['size']?.toString();
      final crustName = map['crust']?.toString();
      final size = _pizzaSizeFromStored(sizeName);
      final crust = _pizzaCrustFromStored(crustName);
      if (size == null || crust == null) return null;

      final rawTopplings = map['toppings'];
      final toppings = <ToppingOption>[
        if (rawTopplings is List)
          for (final raw in rawTopplings.whereType<Map<String, dynamic>>())
            ToppingOption(
              name: raw['name']?.toString() ?? '',
              price: (raw['price'] as num?)?.toDouble() ?? 0,
              icon: raw['icon']?.toString() ?? '',
            ),
      ];
      if (toppings.any((t) => t.name.isEmpty)) return null;

      final quantity = map['quantity'] is int ? map['quantity'] as int : null;
      if (quantity == null || quantity < 1) return null;

      final rawBasePrice = rawItem['basePrice'];
      if (rawBasePrice is! num) return null;

      final rawOriginalPrice = rawItem['originalPrice'];
      final itemId = rawItem['id']?.toString() ?? '';
      if (itemId.isEmpty) return null;

      final item = MenuItem(
        id: itemId,
        title: rawItem['title']?.toString() ?? '',
        description: rawItem['description']?.toString() ?? '',
        basePrice: rawBasePrice.toDouble(),
        originalPrice:
            rawOriginalPrice is num ? rawOriginalPrice.toDouble() : null,
        imageUrl: rawItem['imageUrl']?.toString() ?? '',
        categoryId: rawItem['categoryId']?.toString(),
        categoryName: rawItem['categoryName']?.toString() ?? '',
        isVeg: rawItem['isVeg'] == true,
        isSpicy: rawItem['isSpicy'] == true,
      );

      return CartItem(
        id: lineIdentity(item.id, size, crust, toppings),
        item: item,
        size: size,
        crust: crust,
        selectedToppings: toppings,
        quantity: quantity,
        specialInstructions: map['instructions']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  double get unitPrice {
    double price = item.basePrice * size.priceMultiplier + crust.extraPrice;
    for (final topping in selectedToppings) {
      price += topping.price;
    }
    return price;
  }

  double get totalPrice => unitPrice * quantity;

  /// A rebuilt line keeps the stored [CartItem] shape but carries fresh item
  /// data, which is how a repriced menu now shows through the cart.
  CartItem withMenuItem(MenuItem freshItem) {
    return CartItem(
      id: lineIdentity(freshItem.id, size, crust, selectedToppings),
      item: freshItem,
      size: size,
      crust: crust,
      selectedToppings: selectedToppings,
      quantity: quantity,
      specialInstructions: specialInstructions,
    );
  }

  CartItem copyWith({
    int? quantity,
    String? specialInstructions,
  }) {
    return CartItem(
      id: id,
      item: item,
      size: size,
      crust: crust,
      selectedToppings: selectedToppings,
      quantity: quantity ?? this.quantity,
      specialInstructions: specialInstructions ?? this.specialInstructions,
    );
  }
}
