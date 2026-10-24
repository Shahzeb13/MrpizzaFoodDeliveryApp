import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/menu/data/favorites_repository.dart';
import 'package:mrpizza/features/menu/data/menu_catalog.dart';
import 'package:mrpizza/features/menu/data/menu_repository.dart';
import 'package:mrpizza/features/menu/providers/menu_provider.dart';
import 'package:mrpizza/features/menu/screens/menu_screen.dart';
import 'package:mrpizza/features/profile/providers/profile_provider.dart';
import 'package:mrpizza/features/profile/screens/favorites_screen.dart';

/// Saved dishes used to be a `Set<String>` held in memory. That lost every
/// customer's favourites on restart and handed the previous account's list to
/// whoever signed in next on a shared phone — so these cases pin the list to
/// the account and to the database.
MenuCatalog _catalog() => MenuCatalog.fromRows(
      itemRows: const [
        {
          'id': 'i1',
          'name': 'Afghani Tikka',
          'description': 'Spicy tikka pizza',
          'price': 1290,
          'category_id': 'c-pizza',
        },
        {
          'id': 'i2',
          'name': 'Zinger Burger',
          'description': 'Crispy fillet burger',
          'price': 590,
          'category_id': 'c-burgers',
        },
      ],
      categoryRows: const [
        {'id': 'c-pizza', 'name': 'Pizza Flavours', 'sort_order': 0},
        {'id': 'c-burgers', 'name': 'Burgers', 'sort_order': 1},
      ],
    );

/// Records every write so a test can assert what actually reached the database.
class _RecordingFavoritesRepository implements FavoritesRepository {
  _RecordingFavoritesRepository({this.saved = const []});

  List<String> saved;
  final added = <String>[];
  final removed = <String>[];

  @override
  Future<List<String>> fetchFavoriteItemIds(String userId) async =>
      List<String>.from(saved);

  @override
  Future<void> addFavorite({
    required String userId,
    required String itemId,
  }) async {
    added.add(itemId);
    saved = [...saved, itemId];
  }

  @override
  Future<void> removeFavorite({
    required String userId,
    required String itemId,
  }) async {
    removed.add(itemId);
    saved = saved.where((id) => id != itemId).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Refuses every write, standing in for a dropped connection.
class _FailingFavoritesRepository extends _RecordingFavoritesRepository {
  _FailingFavoritesRepository({super.saved = const []});

  @override
  Future<void> addFavorite({
    required String userId,
    required String itemId,
  }) async =>
      throw Exception('offline');

  @override
  Future<void> removeFavorite({
    required String userId,
    required String itemId,
  }) async =>
      throw Exception('offline');
}

class _FakeMenuRepository implements MenuRepository {
  @override
  Future<MenuCatalog> fetchMenuCatalog() async => _catalog();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Stands in for the real signed-in id, so a test can sign a different
/// customer in without tearing the container down.
final signedInUser = StateProvider<String?>((ref) => 'customer-uuid');

ProviderContainer _container({
  FavoritesRepository? favorites,
  String? userId = 'customer-uuid',
}) {
  final container = ProviderContainer(
    overrides: [
      signedInUser.overrideWith((ref) => userId),
      menuRepositoryProvider.overrideWith((ref) => _FakeMenuRepository()),
      favoritesRepositoryProvider
          .overrideWith((ref) => favorites ?? _RecordingFavoritesRepository()),
      currentUserIdProvider.overrideWith((ref) => ref.watch(signedInUser)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _settle(
  WidgetTester tester,
  ProviderContainer container,
  Widget child,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: child),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

/// [MenuScreen] runs a repeating animation, so `pumpAndSettle` never returns.
/// Pump a fixed span instead, the way `menu_screen_test.dart` does.
Future<void> _settleMenu(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MenuScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('the saved list belongs to the signed-in customer', () {
    test('is read from the database, not remembered in memory', () async {
      final container = _container(
        favorites: _RecordingFavoritesRepository(saved: ['i1', 'i2']),
      );

      expect(await container.read(favoritesProvider.future), ['i1', 'i2']);
    });

    test('signed out there is nothing to read and nothing is asked for',
        () async {
      final container = _container(userId: null);

      expect(await container.read(favoritesProvider.future), isEmpty);
    });

    test('signing out drops the previous account list', () async {
      final repository = _RecordingFavoritesRepository(saved: ['i1']);
      final container = _container(favorites: repository);

      expect(await container.read(favoritesProvider.future), ['i1']);

      // A shared phone signs the next customer in without restarting the app.
      // Without this the newcomer sees the previous account's saved dishes.
      container.read(signedInUser.notifier).state = null;
      await container.read(favoritesProvider.future);

      expect(container.read(favoritesProvider).valueOrNull, isEmpty);
      expect(repository.saved, ['i1'], reason: 'the rows are still there');
    });
  });

  group('tapping the heart', () {
    test('saves a dish through the database', () async {
      final repository = _RecordingFavoritesRepository();
      final container = _container(favorites: repository);
      await container.read(favoritesProvider.future);

      await container.read(favoritesProvider.notifier).toggleFavorite('i1');

      expect(repository.added, ['i1']);
      expect(container.read(favoritesProvider).valueOrNull, ['i1']);
    });

    test('fills the heart before the write lands', () async {
      final container = _container();
      await container.read(favoritesProvider.future);

      // Deliberately not awaited: the heart is already filled while the write
      // is still in flight, which is what makes the tap feel like it worked.
      final pending =
          container.read(favoritesProvider.notifier).toggleFavorite('i1');
      expect(container.read(favoritesProvider).valueOrNull, ['i1']);

      await pending;
    });

    test('tapping a saved dish again removes it', () async {
      final repository = _RecordingFavoritesRepository(saved: ['i1']);
      final container = _container(favorites: repository);
      await container.read(favoritesProvider.future);

      await container.read(favoritesProvider.notifier).toggleFavorite('i1');

      expect(repository.removed, ['i1']);
      expect(repository.added, isEmpty);
      expect(container.read(favoritesProvider).valueOrNull, isEmpty);
    });

    test('a tap landing before the read returns is not lost', () async {
      final repository = _RecordingFavoritesRepository(saved: ['i2']);
      final container = _container(favorites: repository);

      // No await on the read first: the heart is tapped mid-load.
      final load = container.read(favoritesProvider.future);
      final toggle =
          container.read(favoritesProvider.notifier).toggleFavorite('i1');
      await Future.wait([load, toggle]);

      // The arriving read must not overwrite the choice just made.
      expect(container.read(favoritesProvider).valueOrNull, ['i1', 'i2']);
    });

    test('a failed removal puts the heart back and tells the caller', () async {
      final container =
          _container(favorites: _FailingFavoritesRepository(saved: ['i1']));
      await container.read(favoritesProvider.future);

      await expectLater(
        container.read(favoritesProvider.notifier).toggleFavorite('i1'),
        throwsA(anything),
      );

      // Still saved, because the removal never happened. Leaving it unsaved
      // would tell the customer their dish is gone when it is not.
      expect(container.read(favoritesProvider).valueOrNull, ['i1']);
    });

    test('the newest save leads the list', () async {
      final container = _container();
      await container.read(favoritesProvider.future);

      await container.read(favoritesProvider.notifier).toggleFavorite('i1');
      await container.read(favoritesProvider.notifier).toggleFavorite('i2');

      expect(container.read(favoritesProvider).valueOrNull, ['i2', 'i1']);
    });
  });

  group('the heart on a menu card', () {
    testWidgets('is drawn on every dish', (tester) async {
      final container = _container();

      await _settleMenu(tester, container);

      expect(find.byIcon(Icons.favorite_border_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    });

    testWidgets('saving a dish fills its heart and reaches the database',
        (tester) async {
      final repository = _RecordingFavoritesRepository();
      final container = _container(favorites: repository);

      await _settleMenu(tester, container);
      await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
      await tester.pump();
      // Past the toast's own 1.8s dismissal timer, which would otherwise be
      // left pending when the tree is torn down.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));

      expect(repository.added, ['i1']);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    });
  });

  group('the favourites screen', () {
    testWidgets('lists the dishes the customer saved', (tester) async {
      final container = _container(
        favorites: _RecordingFavoritesRepository(saved: ['i2']),
      );

      await _settle(tester, container, const FavoritesScreen());

      expect(find.text('Zinger Burger'), findsOneWidget);
      expect(find.text('Afghani Tikka'), findsNothing);
    });

    testWidgets('says so when there is genuinely nothing saved',
        (tester) async {
      final container = _container();

      await _settle(tester, container, const FavoritesScreen());

      expect(find.text('No Favourites Saved'), findsOneWidget);
    });

    testWidgets('removing a row drops it from the database', (tester) async {
      final repository = _RecordingFavoritesRepository(saved: ['i1', 'i2']);
      final container = _container(favorites: repository);

      await _settle(tester, container, const FavoritesScreen());

      await tester.tap(find.byIcon(Icons.favorite_rounded).first);
      await tester.pumpAndSettle();

      expect(repository.removed, ['i1']);
      expect(find.text('Afghani Tikka'), findsNothing);
      expect(find.text('Zinger Burger'), findsOneWidget);
    });
  });
}
