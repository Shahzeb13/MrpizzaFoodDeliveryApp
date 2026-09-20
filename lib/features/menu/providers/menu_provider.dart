import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/menu_repository.dart';
import '../models/menu_item.dart';

// Selected Category Provider
final selectedCategoryProvider = StateProvider<ItemCategory?>((ref) => null);

// Search Query Provider
final searchQueryProvider = StateProvider<String>((ref) => '');

// Repository + live menu catalog (Supabase `menu_items` with mock fallback).
final menuRepositoryProvider =
    Provider<MenuRepository>((ref) => MenuRepository());

/// The full menu catalog. Waiting/error states surface the bundled mock
/// catalog so screens always have items to render.
final menuFutureProvider = FutureProvider<List<MenuItem>>((ref) {
  return ref.watch(menuRepositoryProvider).fetchMenuItems();
});

// Filtered Menu Items Provider
final filteredMenuItemsProvider = Provider<List<MenuItem>>((ref) {
  final category = ref.watch(selectedCategoryProvider);
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final items =
      ref.watch(menuFutureProvider).value ?? MenuRepository.mockMenuItems;

  return items.where((item) {
    final matchesCategory = category == null || item.category == category;
    final matchesQuery = query.isEmpty ||
        item.title.toLowerCase().contains(query) ||
        item.description.toLowerCase().contains(query);
    return matchesCategory && matchesQuery;
  }).toList();
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
