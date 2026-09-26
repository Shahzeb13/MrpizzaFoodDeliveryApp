import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/menu/data/menu_catalog.dart';
import 'package:mrpizza/features/menu/data/menu_repository.dart';
import 'package:mrpizza/features/menu/models/menu_category.dart';
import 'package:mrpizza/features/menu/models/menu_item.dart';

/// The menu screen showed every item under one heading because the app read a
/// `category` column that does not exist. `menu_items` only has `category_id`,
/// and the 16 rows in `categories` were never fetched at all.
void main() {
  group('MenuItem.fromMap reads category_id', () {
    test('takes the category id from the real foreign key column', () {
      final item = MenuItem.fromMap({
        'id': 'item-1',
        'name': 'Afghani Tikka',
        'description': 'Spicy tikka on a thin crust',
        'price': 1290,
        'image_url': 'https://cdn.example.com/afghani-tikka-pizza.png',
        'category_id': 'e0ae9be8-7e29-4dcb-8cce-d4d877647783',
      });

      expect(item.categoryId, 'e0ae9be8-7e29-4dcb-8cce-d4d877647783');
    });

    test('resolves the category name from the embedded category row', () {
      final item = MenuItem.fromMap({
        'id': 'item-1',
        'name': 'Afghani Tikka',
        'description': 'Spicy tikka on a thin crust',
        'price': 1290,
        'image_url': 'https://cdn.example.com/afghani-tikka-pizza.png',
        'category_id': 'e0ae9be8-7e29-4dcb-8cce-d4d877647783',
        'categories': {'id': 'e0ae9be8-7e29-4dcb-8cce-d4d877647783', 'name': 'Pizza Flavours', 'sort_order': 5},
      });

      expect(item.categoryName, 'Pizza Flavours');
    });

    test('falls back to the separate categories map when nothing is embedded',
        () {
      final item = MenuItem.fromMap(
        {
          'id': 'item-1',
          'name': 'Zinger Burger',
          'description': 'Crispy fillet',
          'price': 590,
          'image_url': 'https://cdn.example.com/zinger.png',
          'category_id': 'cat-burgers',
        },
        categoriesById: {
          'cat-burgers': const MenuCategory(
            id: 'cat-burgers',
            name: 'Burgers',
            sortOrder: 7,
          ),
        },
      );

      expect(item.categoryName, 'Burgers');
    });

    test('keeps the item when its category is unknown instead of dropping it',
        () {
      final item = MenuItem.fromMap({
        'id': 'item-9',
        'name': 'Mystery Item',
        'description': 'No category row',
        'price': 100,
        'image_url': 'https://cdn.example.com/mystery.png',
        'category_id': 'cat-missing',
      });

      expect(item.id, 'item-9');
      expect(item.categoryId, 'cat-missing');
      expect(item.categoryName, isEmpty);
    });

    test('tolerates a row with no category at all', () {
      final item = MenuItem.fromMap({
        'id': 'item-10',
        'name': 'Loose Item',
        'description': 'No category id',
        'price': 100,
        'image_url': 'https://cdn.example.com/loose.png',
      });

      expect(item.categoryId, isNull);
      expect(item.categoryName, isEmpty);
    });
  });

  group('MenuCategory.fromMap', () {
    test('reads id, name and sort order', () {
      final category = MenuCategory.fromMap({
        'id': '5245209f-2525-4b51-9b78-009eee6bbf56',
        'name': 'Birthday & Party Deal',
        'sort_order': 0,
      });

      expect(category.id, '5245209f-2525-4b51-9b78-009eee6bbf56');
      expect(category.name, 'Birthday & Party Deal');
      expect(category.sortOrder, 0);
    });

    test('treats a missing sort order as last', () {
      final category = MenuCategory.fromMap({
        'id': 'c1',
        'name': 'Late Arrival',
      });

      expect(category.sortOrder, MenuCategory.unsortedSortOrder);
    });
  });

  group('MenuCatalog', () {
    test('a named helper builds an item that knows its category', () {
      final item = MenuItem.fromMap(
        {
          'id': 'i1',
          'name': 'Item i1',
          'description': 'Tasty',
          'price': 500,
          'image_url': 'https://cdn.example.com/i1.png',
          'category_id': 'cat-pizza',
        },
        categoriesById: const {
          'cat-pizza': MenuCategory(
            id: 'cat-pizza',
            name: 'Pizza Flavours',
            sortOrder: 5,
          ),
        },
      );

      expect(item.categoryId, 'cat-pizza');
      expect(item.categoryName, 'Pizza Flavours');
    });

    test('orders categories by sort_order, not by name or row order', () {
      final catalog = MenuCatalog.fromRows(
        itemRows: const [],
        categoryRows: [
          {'id': 'cat-pizza', 'name': 'Pizza Flavours', 'sort_order': 5},
          {'id': 'cat-deals', 'name': 'Crispy Deals', 'sort_order': 1},
          {'id': 'cat-burgers', 'name': 'Burgers', 'sort_order': 7},
        ],
      );

      expect(
        catalog.categories.map((c) => c.name).toList(),
        ['Crispy Deals', 'Pizza Flavours', 'Burgers'],
      );
    });

    test('splits items across their real categories', () {
      final catalog = MenuCatalog.fromRows(
        itemRows: [
          {
            'id': 'i1',
            'name': 'Tikka',
            'description': 'x',
            'price': 1,
            'image_url': 'a',
            'category_id': 'cat-pizza',
          },
          {
            'id': 'i2',
            'name': 'Zinger',
            'description': 'x',
            'price': 1,
            'image_url': 'a',
            'category_id': 'cat-burgers',
          },
          {
            'id': 'i3',
            'name': 'Family Deal',
            'description': 'x',
            'price': 1,
            'image_url': 'a',
            'category_id': 'cat-deals',
          },
        ],
        categoryRows: [
          {'id': 'cat-pizza', 'name': 'Pizza Flavours', 'sort_order': 5},
          {'id': 'cat-burgers', 'name': 'Burgers', 'sort_order': 7},
          {'id': 'cat-deals', 'name': 'Crispy Deals', 'sort_order': 1},
        ],
      );

      expect(catalog.itemsIn('cat-pizza').map((i) => i.id).toList(), ['i1']);
      expect(catalog.itemsIn('cat-burgers').map((i) => i.id).toList(), ['i2']);
      expect(catalog.itemsIn('cat-deals').map((i) => i.id).toList(), ['i3']);
    });

    test('reports every item it was given, so nothing silently disappears', () {
      final catalog = MenuCatalog.fromRows(
        itemRows: [
          {
            'id': 'i1',
            'name': 'Tikka',
            'description': 'x',
            'price': 1,
            'image_url': 'a',
            'category_id': 'cat-pizza',
          },
          {
            'id': 'i2',
            'name': 'Loose',
            'description': 'x',
            'price': 1,
            'image_url': 'a',
          },
        ],
        categoryRows: [
          {'id': 'cat-pizza', 'name': 'Pizza Flavours', 'sort_order': 5},
        ],
      );

      expect(catalog.allItems.length, 2);
    });

    test('never claims a category holds an item that belongs to another', () {
      final catalog = MenuCatalog.fromRows(
        itemRows: [
          {
            'id': 'i1',
            'name': 'Tikka',
            'description': 'x',
            'price': 1,
            'image_url': 'a',
            'category_id': 'cat-pizza',
          },
          {
            'id': 'i2',
            'name': 'Loose',
            'description': 'x',
            'price': 1,
            'image_url': 'a',
          },
        ],
        categoryRows: [
          {'id': 'cat-pizza', 'name': 'Pizza Flavours', 'sort_order': 5},
        ],
      );

      final inPizza = catalog.itemsIn('cat-pizza').map((i) => i.id).toList();

      expect(inPizza, ['i1']);
      expect(inPizza, isNot(contains('i2')));
    });

    test('groups an item whose category row is missing under the uncategorized id',
        () {
      final catalog = MenuCatalog.fromRows(
        itemRows: [
          {
            'id': 'i1',
            'name': 'Loose',
            'description': 'x',
            'price': 1,
            'image_url': 'a',
            'category_id': 'cat-missing',
          },
        ],
        categoryRows: const [],
      );

      expect(catalog.allItems.length, 1);
      expect(catalog.itemsIn('cat-missing').length, 1);
    });
  });

  group('MenuRepository relative image paths', () {
    test('turns a stored relative path into a loadable absolute URL', () {
      final absolute = MenuRepository.resolveImageUrl(
        '/menu-images/zinger.png',
        baseUrl: 'https://panel.example.com',
      );

      expect(absolute, 'https://panel.example.com/menu-images/zinger.png');
    });

    test('joins a relative path that has no leading slash', () {
      final absolute = MenuRepository.resolveImageUrl(
        'menu-images/zinger.png',
        baseUrl: 'https://panel.example.com',
      );

      expect(absolute, 'https://panel.example.com/menu-images/zinger.png');
    });

    test('leaves an absolute Cloudinary URL exactly as it is', () {
      const cloudinary =
          'https://res.cloudinary.com/demo/image/upload/v1/mr-pizza-menu/zinger.jpg';

      expect(
        MenuRepository.resolveImageUrl(
          cloudinary,
          baseUrl: 'https://panel.example.com',
        ),
        cloudinary,
      );
    });

    test('leaves an empty image path empty rather than inventing a URL', () {
      expect(
        MenuRepository.resolveImageUrl('', baseUrl: 'https://panel.example.com'),
        isEmpty,
      );
    });

    test('leaves a relative path alone when no base is configured', () {
      expect(
        MenuRepository.resolveImageUrl(
          '/menu-images/zinger.png',
          baseUrl: '',
        ),
        '/menu-images/zinger.png',
      );
    });
  });
}
