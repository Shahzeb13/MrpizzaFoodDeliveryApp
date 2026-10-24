import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../profile/providers/profile_provider.dart';
import '../data/favorites_repository.dart';
import '../data/menu_catalog.dart';
import '../data/menu_repository.dart';
import '../models/menu_category.dart';
import '../models/menu_item.dart';

// The category the customer is browsing, as a `categories.id`. Null means the
// "All" tab, which shows every item rather than one section.
final selectedCategoryIdProvider = StateProvider<String?>((ref) => null);

// Search Query Provider
final searchQueryProvider = StateProvider<String>((ref) => '');

// Repository + live menu catalog (Supabase `categories` + `menu_items`).
final menuRepositoryProvider =
    Provider<MenuRepository>((ref) => MenuRepository());

/// The real menu: the `categories` rows joined to the `menu_items` rows that
/// point at them.
///
/// While loading or on failure this is empty rather than a bundled sample menu.
/// A customer must never be shown food that is not actually for sale; the
/// screens render a loading state, a retry, or a "nothing on today" message.
final menuCatalogProvider = FutureProvider<MenuCatalog>((ref) {
  return ref.watch(menuRepositoryProvider).fetchMenuCatalog();
});

/// The category tabs, in the order the restaurant arranged them.
final menuCategoriesProvider = Provider<List<MenuCategory>>((ref) {
  return ref.watch(menuCatalogProvider).valueOrNull?.categories ?? const [];
});

/// Every item, for screens that show everything (favourites, search-all).
final allMenuItemsProvider = Provider<List<MenuItem>>((ref) {
  return ref.watch(menuCatalogProvider).valueOrNull?.allItems ?? const [];
});

// Filtered Menu Items Provider
final filteredMenuItemsProvider = Provider<List<MenuItem>>((ref) {
  final categoryId = ref.watch(selectedCategoryIdProvider);
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final catalog =
      ref.watch(menuCatalogProvider).valueOrNull ?? MenuCatalog.empty;

  final pool =
      categoryId == null ? catalog.allItems : catalog.itemsIn(categoryId);
  if (query.isEmpty) return pool;

  return pool
      .where((item) =>
          item.title.toLowerCase().contains(query) ||
          item.description.toLowerCase().contains(query) ||
          item.categoryName.toLowerCase().contains(query))
      .toList();
});

/// The `menu_items.id` values the signed-in customer has hearted, newest first.
///
/// These were a plain `Set<String>` in memory, which meant a customer's saved
/// dishes vanished on restart and the next account to sign in on a shared phone
/// was shown the previous customer's favourites. Watching [currentUserIdProvider]
/// inside [build] is what ties the list to the account: signing out, or signing
/// in as somebody else, re-runs the read instead of inheriting stale ids.
class FavoritesNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      // Signed out: there is no row to read, and no favourites surface is
      // reachable behind the router. Returning immediately also keeps the app
      // from waiting on a query that cannot run.
      return const [];
    }
    return ref.watch(favoritesRepositoryProvider).fetchFavoriteItemIds(userId);
  }

  /// Saves [itemId] if it is not saved, removes it if it is.
  ///
  /// The heart fills immediately and the write happens behind it, because a
  /// round trip to the database is slow enough that an instant response is the
  /// difference between the feature feeling real and feeling broken. A failed
  /// write puts the list back exactly as it was and rethrows, so the button can
  /// tell the customer their tap did not stick.
  Future<void> toggleFavorite(String itemId) async {
    // A tap can land before the first read returns, and that read would then
    // overwrite the choice just made. Waiting for it keeps the two in order.
    if (state.isLoading) {
      try {
        await future;
      } catch (_) {
        // The load failed, so there is no list for it to disagree with. Carry
        // on and let the write below decide whether the tap took.
      }
    }

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final before = state;
    final saved = before.valueOrNull ?? const <String>[];

    state = AsyncData(
      saved.contains(itemId)
          ? saved.where((id) => id != itemId).toList()
          : [itemId, ...saved],
    );

    try {
      final repository = ref.read(favoritesRepositoryProvider);
      if (saved.contains(itemId)) {
        await repository.removeFavorite(userId: userId, itemId: itemId);
      } else {
        await repository.addFavorite(userId: userId, itemId: itemId);
      }
    } catch (_) {
      state = before;
      rethrow;
    }
  }
}

final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, List<String>>(
  FavoritesNotifier.new,
);

/// Whether [itemId] is currently hearted.
///
/// An unread list answers false, which draws the empty heart rather than a
/// placeholder. A heart that briefly reads as unsaved while the list loads is
/// far less alarming than a blank circle, and the tap is recorded either way.
bool isFavorite(AsyncValue<List<String>> favorites, String itemId) =>
    favorites.valueOrNull?.contains(itemId) ?? false;

// Cart State
class CartState {
  final List<CartItem> items;

  const CartState({required this.items});

  bool get isEmpty => items.isEmpty;

  int get totalItemCount => items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.totalPrice);

  CartState copyWith({List<CartItem>? items}) {
    return CartState(items: items ?? this.items);
  }
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(const CartState(items: []));

  void addItem({
    required MenuItem item,
    required PizzaSize size,
    required PizzaCrust crust,
    required List<ToppingOption> toppings,
    int quantity = 1,
    String? instructions,
  }) {
    final cartItemId = '${item.id}_${size.name}_${crust.name}_${toppings.map((t) => t.name).join('_')}';

    final existingIndex = state.items.indexWhere((i) => i.id == cartItemId);

    if (existingIndex >= 0) {
      final updatedItems = [...state.items];
      final current = updatedItems[existingIndex];
      updatedItems[existingIndex] = current.copyWith(
        quantity: current.quantity + quantity,
        specialInstructions: instructions ?? current.specialInstructions,
      );
      state = state.copyWith(items: updatedItems);
    } else {
      final newItem = CartItem(
        id: cartItemId,
        item: item,
        size: size,
        crust: crust,
        selectedToppings: toppings,
        quantity: quantity,
        specialInstructions: instructions,
      );
      state = state.copyWith(items: [...state.items, newItem]);
    }
  }

  void updateQuantity(String cartItemId, int delta) {
    final updatedItems = <CartItem>[];
    for (final item in state.items) {
      if (item.id == cartItemId) {
        final newQty = item.quantity + delta;
        if (newQty > 0) {
          updatedItems.add(item.copyWith(quantity: newQty));
        }
      } else {
        updatedItems.add(item);
      }
    }
    state = state.copyWith(items: updatedItems);
  }

  void removeItem(String cartItemId) {
    state = state.copyWith(
      items: state.items.where((item) => item.id != cartItemId).toList(),
    );
  }

  void clearCart() {
    state = const CartState(items: []);
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});
