import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../../core/network/supabase_client.dart';
import '../models/menu_category.dart';
import '../models/menu_item.dart';
import 'menu_catalog.dart';

class MenuRepository {
  /// Loads the menu from Supabase: the real `categories` rows plus every
  /// `menu_items` row, joined through `menu_items.category_id`.
  ///
  /// Falls back to the bundled mock catalog when the fetch fails or comes back
  /// empty, so the UI always has something to render.
  Future<MenuCatalog> fetchMenuCatalog() async {
    try {
      // PostgREST embeds `categories` through the real foreign key
      // (menu_items_category_id_fkey), so one round trip is enough.
      final itemRows = await supabase
          .from('menu_items')
          .select('*, categories(id, name, sort_order)');
      final items = (itemRows as List).whereType<Map<String, dynamic>>();

      final categoryRows = await supabase
          .from('categories')
          .select('id, name, sort_order')
          .order('sort_order', ascending: true);

      final catalog = MenuCatalog.fromRows(
        itemRows: items.toList(),
        categoryRows:
            (categoryRows as List).whereType<Map<String, dynamic>>().toList(),
      );

      if (catalog.isEmpty) return mockCatalog;
      return catalog;
    } catch (_) {
      return mockCatalog;
    }
  }

  /// Base URL that relative `image_url` values are resolved against.
  ///
  /// Rows written before the Cloudinary migration store a bare path such as
  /// `/menu-images/zinger.png`, which `Image.network` cannot load. Those are
  /// resolved against this base; absolute URLs are passed through untouched, so
  /// the app works with either storage backend at once.
  static String get imageBaseUrl {
    if (_cachedBaseUrl != null) return _cachedBaseUrl!;
    try {
      _cachedBaseUrl = dotenv.maybeGet('MENU_IMAGE_BASE_URL')?.trim() ?? '';
    } catch (_) {
      // The .env asset is unavailable in unit tests.
      _cachedBaseUrl = '';
    }
    return _cachedBaseUrl!;
  }

  static String? _cachedBaseUrl;

  @visibleForTesting
  static void overrideImageBaseUrl(String value) => _cachedBaseUrl = value.trim();

  /// Turns a stored `image_url` into something `Image.network` can load.
  ///
  /// Absolute `http(s)` URLs are returned unchanged, so Cloudinary URLs keep
  /// working. A relative path is joined onto [baseUrl]. An empty value stays
  /// empty rather than becoming a broken request, which lets the caller show
  /// its own placeholder.
  static String resolveImageUrl(String raw, {String? baseUrl}) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    final base = (baseUrl ?? imageBaseUrl).trim();
    if (base.isEmpty) return value;
    final separator = value.startsWith('/') ? '' : '/';
    return '$base$separator$value';
  }

  /// Resolved image URL for a loaded item.
  static String resolveItemImage(MenuItem item) =>
      resolveImageUrl(item.imageUrl);

  static const List<ToppingOption> defaultToppings = [
    ToppingOption(name: 'Extra Mozzarella', price: 150.0, icon: '🧀'),
    ToppingOption(name: 'Pepperoni Slices', price: 180.0, icon: '🥩'),
    ToppingOption(name: 'Fresh Basil Leaves', price: 80.0, icon: '🌱'),
    ToppingOption(name: 'Jalapeño Peppers', price: 100.0, icon: '🌶️'),
    ToppingOption(name: 'Black Olives', price: 90.0, icon: '🫒'),
    ToppingOption(name: 'Truffle Oil Drizzle', price: 220.0, icon: '✨'),
  ];

  /// Offline catalog used when Supabase is unreachable. Categories mirror the
  /// real menu shape so the fallback still divides the menu sensibly.
  static const List<MenuCategory> mockCategories = [
    MenuCategory(id: 'mock-deals', name: 'Deals & Offers', sortOrder: 0),
    MenuCategory(id: 'mock-pizza', name: 'Pizza Flavours', sortOrder: 1),
    MenuCategory(id: 'mock-burgers', name: 'Burgers', sortOrder: 2),
    MenuCategory(id: 'mock-wraps', name: 'Wraps & Rolls', sortOrder: 3),
    MenuCategory(id: 'mock-chicken', name: 'Crispy Chicken', sortOrder: 4),
    MenuCategory(id: 'mock-sides', name: 'Sides & Starters', sortOrder: 5),
    MenuCategory(id: 'mock-drinks', name: 'Beverages', sortOrder: 6),
  ];

  static final MenuCatalog mockCatalog = MenuCatalog.fromRows(
    itemRows: [
      {
        'id': 'mock_1',
        'name': 'Chicken Fajita',
        'description':
            'Marinated fajita chicken, bell peppers, onions, fresh mozzarella & signature tomato sauce.',
        'price': 990,
        'image_url':
            'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=800&q=85',
        'category_id': 'mock-pizza',
        'is_bestseller': true,
      },
      {
        'id': 'mock_2',
        'name': 'Chicken Supreme',
        'description':
            'Smoked chicken, pepperoni, mushrooms, black olives, onions & green bell peppers.',
        'price': 1150,
        'image_url':
            'https://images.unsplash.com/photo-1628840042765-356cda07504e?auto=format&fit=crop&w=800&q=85',
        'category_id': 'mock-pizza',
        'is_bestseller': true,
      },
      {
        'id': 'mock_3',
        'name': 'Crown Crust Special',
        'description':
            'Stuffed cheese crown crust topped with smoked chicken, beef pepperoni, olives & truffle cream.',
        'price': 1490,
        'image_url':
            'https://images.unsplash.com/photo-1595708684082-a173bb3a06c5?auto=format&fit=crop&w=800&q=85',
        'category_id': 'mock-deals',
        'is_bestseller': true,
      },
      {
        'id': 'mock_4',
        'name': 'Zinger Supreme Burger',
        'description':
            'Crispy deep-fried chicken fillet with garlic mayo, iceberg lettuce, and melted cheese slice.',
        'price': 590,
        'image_url':
            'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=800&q=85',
        'category_id': 'mock-burgers',
        'is_bestseller': true,
      },
      {
        'id': 'mock_5',
        'name': 'Smokey Beef House Burger',
        'description':
            'Flame-grilled double beef patty, smoked bacon, caramelized onions & signature BBQ mayo.',
        'price': 790,
        'image_url':
            'https://images.unsplash.com/photo-1586190848861-99aa4a171e90?auto=format&fit=crop&w=800&q=85',
        'category_id': 'mock-burgers',
      },
      {
        'id': 'mock_6',
        'name': 'Afghani Wraps',
        'description':
            'Grilled chicken, fresh vegetables and our signature sauce wrapped in a warm paratha.',
        'price': 450,
        'image_url':
            'https://images.unsplash.com/photo-1561651823-34feb02250e4?auto=format&fit=crop&w=800&q=85',
        'category_id': 'mock-wraps',
      },
      {
        'id': 'mock_7',
        'name': 'Crispy Chicken Wings (6 Pcs)',
        'description':
            'Crispy chicken wings tossed in fiery original Buffalo sauce.',
        'price': 490,
        'image_url':
            'https://images.unsplash.com/photo-1567620832903-9fc6debc209f?auto=format&fit=crop&w=800&q=85',
        'category_id': 'mock-chicken',
        'is_spicy': true,
      },
      {
        'id': 'mock_8',
        'name': 'Garlic Cheese Knots',
        'description':
            'Freshly baked dough knots coated in garlic herb butter & served with marinara.',
        'price': 390,
        'image_url':
            'https://images.unsplash.com/photo-1541745537411-b8046dc6d66c?auto=format&fit=crop&w=800&q=85',
        'category_id': 'mock-sides',
      },
      {
        'id': 'mock_9',
        'name': 'Pepsi Chilled Bottle (1.5L)',
        'description': '1.5 Liter ice-cold refreshing cola beverage.',
        'price': 220,
        'image_url':
            'https://images.unsplash.com/photo-1622483767028-3f66f32aef97?auto=format&fit=crop&w=800&q=85',
        'category_id': 'mock-drinks',
        'is_bestseller': true,
      },
    ],
    categoryRows: [
      for (final category in mockCategories)
        {
          'id': category.id,
          'name': category.name,
          'sort_order': category.sortOrder,
        },
    ],
  );
}
