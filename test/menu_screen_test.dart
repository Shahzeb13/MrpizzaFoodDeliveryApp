import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/menu/data/menu_catalog.dart';
import 'package:mrpizza/features/menu/data/menu_repository.dart';
import 'package:mrpizza/features/menu/providers/menu_provider.dart';
import 'package:mrpizza/features/menu/screens/menu_screen.dart';

/// The menu screen put all 88 items under one heading because it read a
/// `category` column that does not exist and never fetched `categories`.
void main() {
  MenuCatalog catalogWithTwoRealCategories() => MenuCatalog.fromRows(
        itemRows: [
          {
            'id': 'i1',
            'name': 'Afghani Tikka',
            'description': 'Spicy tikka pizza',
            'price': 1290,
            'image_url': 'https://cdn.example.com/1.png',
            'category_id': 'c-pizza',
          },
          {
            'id': 'i2',
            'name': 'Zinger Burger',
            'description': 'Crispy fillet burger',
            'price': 590,
            'image_url': 'https://cdn.example.com/2.png',
            'category_id': 'c-burgers',
          },
          {
            'id': 'i3',
            'name': 'Crispy Deal Box',
            'description': 'Two pizzas and wings',
            'price': 2490,
            'image_url': 'https://cdn.example.com/3.png',
            'category_id': 'c-deals',
          },
        ],
        categoryRows: const [
          {'id': 'c-deals', 'name': 'Crispy Deals', 'sort_order': 0},
          {'id': 'c-pizza', 'name': 'Pizza Flavours', 'sort_order': 1},
          {'id': 'c-burgers', 'name': 'Burgers', 'sort_order': 2},
        ],
      );

  Future<ProviderContainer> pumpMenu(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        menuRepositoryProvider.overrideWith(
          (ref) => _FakeMenuRepository(catalogWithTwoRealCategories()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MenuScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return container;
  }

  group('menu categories come from the database', () {
    testWidgets('shows a tab for every real category', (tester) async {
      final container = await pumpMenu(tester);

      final categories = container.read(menuCategoriesProvider);

      expect(categories.map((c) => c.name).toList(), [
        'Crispy Deals',
        'Pizza Flavours',
        'Burgers',
      ]);
    });

    testWidgets('the All tab lists every item', (tester) async {
      final container = await pumpMenu(tester);
      final all = container.read(allMenuItemsProvider);

      expect(all.length, 3);
    });

    testWidgets('picking a category narrows to just its own items',
        (tester) async {
      final container = await pumpMenu(tester);

      container.read(selectedCategoryIdProvider.notifier).state = 'c-burgers';
      await tester.pump();

      final filtered = container.read(filteredMenuItemsProvider);

      expect(filtered.length, 1);
      expect(filtered.single.title, 'Zinger Burger');
    });

    testWidgets('an item never leaks into another category', (tester) async {
      final container = await pumpMenu(tester);

      container.read(selectedCategoryIdProvider.notifier).state = 'c-pizza';
      await tester.pump();

      final titles =
          container.read(filteredMenuItemsProvider).map((i) => i.title).toList();

      expect(titles, ['Afghani Tikka']);
      expect(titles, isNot(contains('Zinger Burger')));
      expect(titles, isNot(contains('Crispy Deal Box')));
    });

    testWidgets('search matches the real category name too', (tester) async {
      final container = await pumpMenu(tester);

      container.read(selectedCategoryIdProvider.notifier).state = null;
      container.read(searchQueryProvider.notifier).state = 'burgers';
      await tester.pump();

      final filtered = container.read(filteredMenuItemsProvider);

      expect(filtered.length, 1);
      expect(filtered.single.title, 'Zinger Burger');
    });
  });
}

class _FakeMenuRepository implements MenuRepository {
  final MenuCatalog catalog;
  _FakeMenuRepository(this.catalog);

  @override
  Future<MenuCatalog> fetchMenuCatalog() async => catalog;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
