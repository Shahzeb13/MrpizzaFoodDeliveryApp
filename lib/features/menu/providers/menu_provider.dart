import 'package:flutter_riverpod/flutter_riverpod.dart';
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
/// point at them. Falls back to the bundled offline catalog so screens always
/// have something to render.
final menuCatalogProvider = FutureProvider<MenuCatalog>((ref) {
  return ref.watch(menuRepositoryProvider).fetchMenuCatalog();
});

/// The category tabs, in the order the restaurant arranged them.
final menuCategoriesProvider = Provider<List<MenuCategory>>((ref) {
  return ref.watch(menuCatalogProvider).value?.categories ??
      MenuRepository.mockCategories;
});

/// Every item, for screens that show everything (favourites, search-all).
final allMenuItemsProvider = Provider<List<MenuItem>>((ref) {
  return ref.watch(menuCatalogProvider).value?.allItems ??
      MenuRepository.mockCatalog.allItems;
});

// Filtered Menu Items Provider
final filteredMenuItemsProvider = Provider<List<MenuItem>>((ref) {
  final categoryId = ref.watch(selectedCategoryIdProvider);
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final catalog = ref.watch(menuCatalogProvider).value ?? MenuRepository.mockCatalog;

  final pool = categoryId == null ? catalog.allItems : catalog.itemsIn(categoryId);
  if (query.isEmpty) return pool;

  return pool
      .where((item) =>
          item.title.toLowerCase().contains(query) ||
          item.description.toLowerCase().contains(query) ||
          item.categoryName.toLowerCase().contains(query))
      .toList();
});

// Favorite Items Provider
class FavoritesNotifier extends StateNotifier<Set<String>> {
  FavoritesNotifier() : super(<String>{});

  void toggleFavorite(String itemId) {
    if (state.contains(itemId)) {
      state = {...state}..remove(itemId);
    } else {
      state = {...state, itemId};
    }
  }
}

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, Set<String>>((ref) {
  return FavoritesNotifier();
});

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
