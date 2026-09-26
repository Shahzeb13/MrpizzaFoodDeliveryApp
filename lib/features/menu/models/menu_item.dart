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

  double get unitPrice {
    double price = item.basePrice * size.priceMultiplier + crust.extraPrice;
    for (final topping in selectedToppings) {
      price += topping.price;
    }
    return price;
  }

  double get totalPrice => unitPrice * quantity;

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
