enum ItemCategory {
  classics('Flaming Classics'),
  specials('Flaming Specials'),
  burgers('Juicy Burgers'),
  shawarmas('Shawarmas'),
  desserts('Desserts'),
  deals('Deals & Offers'),
  sides('Sides & Starters'),
  drinks('Beverages');

  final String label;
  const ItemCategory(this.label);

  /// Maps a DB `category` value (enum name or label, any casing) to a
  /// category. Unknown values fall back to [classics] so rows stay visible.
  static ItemCategory fromDb(Object? value) {
    if (value == null) return ItemCategory.classics;
    final s = value.toString().trim().toLowerCase();
    for (final c in ItemCategory.values) {
      if (c.name == s || c.label.toLowerCase() == s) return c;
    }
    const aliases = <String, ItemCategory>{
      'classic': ItemCategory.classics,
      'flaming classic': ItemCategory.classics,
      'special': ItemCategory.specials,
      'flaming special': ItemCategory.specials,
      'burger': ItemCategory.burgers,
      'shawarma': ItemCategory.shawarmas,
      'dessert': ItemCategory.desserts,
      'deal': ItemCategory.deals,
      'offer': ItemCategory.deals,
      'offers': ItemCategory.deals,
      'deals & offers': ItemCategory.deals,
      'side': ItemCategory.sides,
      'starter': ItemCategory.sides,
      'starters': ItemCategory.sides,
      'sides & starters': ItemCategory.sides,
      'drink': ItemCategory.drinks,
      'beverage': ItemCategory.drinks,
    };
    return aliases[s] ?? ItemCategory.classics;
  }
}

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
  final ItemCategory category;
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
    required this.category,
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
  /// resolved tolerantly (title/name, base_price/price, image_url/image, …)
  /// so the mapping keeps working as the table evolves.
  factory MenuItem.fromMap(Map<String, dynamic> map) {
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
      category: ItemCategory.fromDb(map['category']),
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
