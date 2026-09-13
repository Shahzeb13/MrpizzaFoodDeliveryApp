import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/menu_repository.dart';
import '../models/menu_item.dart';

// Selected Category Provider
final selectedCategoryProvider = StateProvider<ItemCategory?>((ref) => null);

// Search Query Provider
final searchQueryProvider = StateProvider<String>((ref) => '');

// Filtered Menu Items Provider
final filteredMenuItemsProvider = Provider<List<MenuItem>>((ref) {
  final category = ref.watch(selectedCategoryProvider);
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();

  return MenuRepository.mockMenuItems.where((item) {
    final matchesCategory = category == null || item.category == category;
    final matchesQuery = query.isEmpty ||
        item.title.toLowerCase().contains(query) ||
        item.description.toLowerCase().contains(query);
    return matchesCategory && matchesQuery;
  }).toList();
});

// Favorite Items Provider
class FavoritesNotifier extends StateNotifier<Set<String>> {
  FavoritesNotifier() : super({'sig_1', 'clas_1', 'des_1'});

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
  final String? promoCode;
  final double discountPercentage;
  final double deliveryFee;
  final double taxRate;

  const CartState({
    required this.items,
    this.promoCode,
    this.discountPercentage = 0.0,
    this.deliveryFee = 2.99,
    this.taxRate = 0.08,
  });

  int get totalItemCount => items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.totalPrice);

  double get discountAmount => subtotal * discountPercentage;

  double get taxAmount => (subtotal - discountAmount) * taxRate;

  double get grandTotal {
    if (items.isEmpty) return 0.0;
    return (subtotal - discountAmount) + taxAmount + deliveryFee;
  }

  CartState copyWith({
    List<CartItem>? items,
    String? promoCode,
    double? discountPercentage,
    double? deliveryFee,
    double? taxRate,
  }) {
    return CartState(
      items: items ?? this.items,
      promoCode: promoCode ?? this.promoCode,
      discountPercentage: discountPercentage ?? this.discountPercentage,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      taxRate: taxRate ?? this.taxRate,
    );
  }
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier()
      : super(
          CartState(
            items: [
              CartItem(
                id: 'cart_demo_1',
                item: MenuRepository.mockMenuItems.firstWhere(
                  (i) => i.id == 'classic_2',
                  orElse: () => MenuRepository.mockMenuItems.first,
                ),
                size: PizzaSize.medium,
                crust: PizzaCrust.cheeseBurst,
                selectedToppings: [
                  MenuRepository.defaultToppings[0],
                  MenuRepository.defaultToppings[2],
                ],
                quantity: 1,
              ),
              CartItem(
                id: 'cart_demo_2',
                item: MenuRepository.mockMenuItems.firstWhere(
                  (i) => i.id == 'side_1',
                  orElse: () => MenuRepository.mockMenuItems.last,
                ),
                size: PizzaSize.small,
                crust: PizzaCrust.thin,
                selectedToppings: [],
                quantity: 2,
              ),
            ],
            promoCode: 'MRPIZZA50',
            discountPercentage: 0.20,
          ),
        );

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

  bool applyPromoCode(String code) {
    final cleaned = code.trim().toUpperCase();
    if (cleaned == 'MRPIZZA50' || cleaned == 'WELCOME50') {
      state = state.copyWith(
        promoCode: cleaned,
        discountPercentage: 0.50, // 50% discount
      );
      return true;
    } else if (cleaned == 'PIZZA20') {
      state = state.copyWith(
        promoCode: cleaned,
        discountPercentage: 0.20,
      );
      return true;
    }
    return false;
  }

  void removePromoCode() {
    state = state.copyWith(
      promoCode: null,
      discountPercentage: 0.0,
    );
  }

  void clearCart() {
    state = state.copyWith(items: []);
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});
