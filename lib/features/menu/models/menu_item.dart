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
