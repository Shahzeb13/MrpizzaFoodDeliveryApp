import '../../../core/network/supabase_client.dart';
import '../models/menu_item.dart';

class MenuRepository {
  /// Loads the menu from the Supabase `menu_items` table.
  ///
  /// Falls back to the bundled mock catalog when the table is empty or the
  /// fetch fails, so the UI always has items to display.
  Future<List<MenuItem>> fetchMenuItems() async {
    try {
      final rows = await supabase.from('menu_items').select();
      final items = (rows as List)
          .whereType<Map<String, dynamic>>()
          .map((row) => MenuItem.fromMap(row))
          .where((item) => item.id.isNotEmpty)
          .toList();
      if (items.isEmpty) return mockMenuItems;
      return items;
    } catch (_) {
      return mockMenuItems;
    }
  }

  static const List<ToppingOption> defaultToppings = [
    ToppingOption(name: 'Extra Mozzarella', price: 150.0, icon: '🧀'),
    ToppingOption(name: 'Pepperoni Slices', price: 180.0, icon: '🥩'),
    ToppingOption(name: 'Fresh Basil Leaves', price: 80.0, icon: '🌱'),
    ToppingOption(name: 'Jalapeño Peppers', price: 100.0, icon: '🌶️'),
    ToppingOption(name: 'Black Olives', price: 90.0, icon: '🫒'),
    ToppingOption(name: 'Truffle Oil Drizzle', price: 220.0, icon: '✨'),
  ];

  static final List<MenuItem> mockMenuItems = [
    // FLAMING CLASSICS
    const MenuItem(
      id: 'classic_1',
      title: 'Chicken Fajita',
      description: 'Marinated fajita chicken, bell peppers, onions, fresh mozzarella & signature tomato sauce.',
      basePrice: 990.0,
      imageUrl: 'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.classics,
      rating: 4.9,
      reviewCount: 420,
      isBestseller: true,
      availableToppings: defaultToppings,
    ),
    const MenuItem(
      id: 'classic_2',
      title: 'Chicken Supreme',
      description: 'Smoked chicken, pepperoni, mushrooms, black olives, onions & green bell peppers.',
      basePrice: 1150.0,
      imageUrl: 'https://images.unsplash.com/photo-1628840042765-356cda07504e?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.classics,
      rating: 4.95,
      reviewCount: 512,
      isBestseller: true,
      availableToppings: defaultToppings,
    ),
    // FLAMING SPECIALS
    const MenuItem(
      id: 'spec_1',
      title: 'Crown Crust Special',
      description: 'Stuffed cheese crown crust topped with smoked chicken, beef pepperoni, olives & truffle cream.',
      basePrice: 1490.0,
      imageUrl: 'https://images.unsplash.com/photo-1595708684082-a173bb3a06c5?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.specials,
      rating: 4.98,
      reviewCount: 680,
      isBestseller: true,
      availableToppings: defaultToppings,
    ),
    const MenuItem(
      id: 'spec_2',
      title: 'Truffle Wild Mushroom Gold',
      description: 'Black truffle ricotta cream base, roasted wild portobello mushrooms & aged parmesan.',
      basePrice: 1390.0,
      imageUrl: 'https://images.unsplash.com/photo-1573821663912-569905455b1c?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.specials,
      rating: 4.9,
      reviewCount: 310,
      isVeg: true,
      availableToppings: defaultToppings,
    ),
    // JUICY BURGERS
    const MenuItem(
      id: 'burg_1',
      title: 'Zinger Supreme Burger',
      description: 'Crispy deep-fried chicken fillet with garlic mayo, iceberg lettuce, and melted cheese slice.',
      basePrice: 590.0,
      imageUrl: 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.burgers,
      rating: 4.92,
      reviewCount: 520,
      isBestseller: true,
    ),
    const MenuItem(
      id: 'burg_2',
      title: 'Smokey Beef House Burger',
      description: 'Flame-grilled double beef patty, smoked bacon, caramelized onions & signature BBQ mayo.',
      basePrice: 790.0,
      imageUrl: 'https://images.unsplash.com/photo-1586190848861-99aa4a171e90?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.burgers,
      rating: 4.95,
      reviewCount: 430,
      isBestseller: true,
    ),
    // SHAWARMAS
    const MenuItem(
      id: 'shawarma_1',
      title: 'Classic Chicken Zinger Shawarma',
      description: 'Crispy chicken zinger strips, pickled cucumbers, fries & garlic mayo wrapped in fresh pita.',
      basePrice: 350.0,
      imageUrl: 'https://images.unsplash.com/photo-1561651823-34feb02250e4?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.shawarmas,
      rating: 4.92,
      reviewCount: 480,
      isBestseller: true,
    ),
    const MenuItem(
      id: 'shawarma_2',
      title: 'Arabian Shawarma Platter',
      description: 'Sliced rotisserie chicken shawarma, garlic dip, pickled veggies, hummus & warm pita bread.',
      basePrice: 550.0,
      imageUrl: 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.shawarmas,
      rating: 4.95,
      reviewCount: 390,
      isBestseller: true,
    ),
    // DESSERTS
    const MenuItem(
      id: 'des_1',
      title: 'Molten Lava Cake',
      description: 'Warm chocolate sponge cake with rich oozing molten dark chocolate center.',
      basePrice: 450.0,
      imageUrl: 'https://images.unsplash.com/photo-1606313564200-e75d5e30476c?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.desserts,
      rating: 4.95,
      reviewCount: 610,
      isVeg: true,
      isBestseller: true,
    ),
    const MenuItem(
      id: 'des_2',
      title: 'Nutella Fudgy Brownie',
      description: 'Rich dark chocolate brownie swirled with warm Nutella hazelnuts.',
      basePrice: 390.0,
      imageUrl: 'https://images.unsplash.com/photo-1564355808539-22fda35bed7e?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.desserts,
      rating: 4.92,
      reviewCount: 390,
      isVeg: true,
      isBestseller: true,
    ),
    // DEALS & OFFERS (MULTI-ITEM BUNDLE COMBO IMAGES)
    const MenuItem(
      id: 'deal_1',
      title: 'Flaming Royal Family Feast',
      description: '2 Large Signature Pizzas + 1 Garlic Breadsticks + Spicy Buffalo Wings + 1.5L Pepsi. Save 35%!',
      basePrice: 2490.0,
      originalPrice: 3490.0,
      imageUrl: 'https://images.unsplash.com/photo-1574071318508-1cdbab80d002?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.deals,
      rating: 4.98,
      reviewCount: 520,
      isBestseller: true,
      availableToppings: defaultToppings,
    ),
    const MenuItem(
      id: 'deal_4',
      title: 'Mega Feast Combo (Pizza + Burgers + Shawarmas)',
      description: '1 Large Pizza + 2 Zinger Burgers + 2 Classic Shawarmas + 1.5L Drink. Save 40%!',
      basePrice: 2990.0,
      originalPrice: 4200.0,
      imageUrl: 'https://images.unsplash.com/photo-1561758033-d89a9ad46330?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.deals,
      rating: 4.99,
      reviewCount: 680,
      isBestseller: true,
      availableToppings: defaultToppings,
    ),

    // SIDES & STARTERS
    const MenuItem(
      id: 'side_1',
      title: 'Garlic Cheese Knots',
      description: 'Freshly baked dough knots coated in garlic herb butter & served with marinara.',
      basePrice: 390.0,
      imageUrl: 'https://images.unsplash.com/photo-1541745537411-b8046dc6d66c?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.sides,
      rating: 4.9,
      reviewCount: 490,
      isVeg: true,
    ),
    const MenuItem(
      id: 'side_2',
      title: 'Spicy Buffalo Wings (6 Pcs)',
      description: 'Crispy chicken wings tossed in fiery original Buffalo sauce.',
      basePrice: 490.0,
      imageUrl: 'https://images.unsplash.com/photo-1567620832903-9fc6debc209f?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.sides,
      rating: 4.88,
      reviewCount: 310,
      isSpicy: true,
    ),
    // BEVERAGES (EXPANDED OPTIONS WITH HD IMAGES)
    const MenuItem(
      id: 'drink_1',
      title: 'Pepsi Chilled Bottle (1.5L)',
      description: '1.5 Liter ice-cold refreshing cola beverage.',
      basePrice: 220.0,
      imageUrl: 'https://images.unsplash.com/photo-1622483767028-3f66f32aef97?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.drinks,
      rating: 4.9,
      reviewCount: 650,
      isBestseller: true,
    ),
    const MenuItem(
      id: 'drink_3',
      title: 'Fresh Mint Margarita Freeze',
      description: 'Chilled crushed ice blend with fresh lemon, mint leaves & sparkling soda.',
      basePrice: 290.0,
      imageUrl: 'https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?auto=format&fit=crop&w=800&q=85',
      category: ItemCategory.drinks,
      rating: 4.95,
      reviewCount: 510,
      isBestseller: true,
    ),
    ];
}
