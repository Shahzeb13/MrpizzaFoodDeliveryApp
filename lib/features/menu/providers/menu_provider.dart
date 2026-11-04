import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/storage/local_storage.dart';
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

  /// Encodes the lines for storage. Empty answers null so the caller removes
  /// the key rather than storing `"[]"`.
  static String? toStorageJson(List<CartItem> lines) {
    if (lines.isEmpty) return null;
    return jsonEncode([for (final line in lines) line.toStorageMap()]);
  }

  /// Reads back what [toStorageJson] wrote. Unreadable lines are dropped one by
  /// one instead of failing the whole cart; anything that cannot be parsed at
  /// all answers null (an empty cart on next start, never a crash).
  static CartState? fromStorageJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final lines = <CartItem>[
        for (final entry in decoded)
          if (entry is Map<String, dynamic>)
            if (CartItem.fromStorageMap(entry) case final line?) line,
      ];
      return CartState(items: lines);
    } catch (_) {
      return null;
    }
  }
}

/// The customer's cart, persisted across app restarts.
///
/// A guest who adds food, closes the app, comes back and finally logs in must
/// still find the cart full — which is why the lines are saved locally through
/// [LocalStore] and restored on first read. The saved copy is best-effort:
/// storage problems leave the in-memory cart working exactly as before.
class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(const CartState(items: [])) {
    // A feature that never shows before some screen watches this provider, so
    // restoring waits for the first read and repairs the empty state within
    // milliseconds. Storage that never opens just leaves the cart empty.
    _storeReady = LocalStore.instance.ready();
    unawaited(_hydrate());
  }

  late final Future<SharedPreferences?> _storeReady;
  bool _changedSinceBoot = false;

  static const _empty = CartState(items: []);

  Future<void> _hydrate() async {
    final prefs = await _storeReady;
    if (prefs == null) return;

    final restored = CartState.fromStorageJson(
      LocalStore.instance.readString(localStorageCartKey),
    );

    // A customer who managed a tap before the read finished has already
    // decided what their cart is; the stored copy is older than that.
    if (!mounted || _changedSinceBoot || restored == null) return;
    if (restored.isEmpty) return;

    state = restored;
  }

  /// Writes the current lines (or removes the key when the cart is empty) once
  /// storage is ready. The lines are read at write time so a burst of quick
  /// taps still ends with the latest cart on disk.
  void _persist() {
    unawaited(() async {
      await _storeReady;
      if (!mounted) return;
      await LocalStore.instance.writeString(
        localStorageCartKey,
        CartState.toStorageJson(state.items),
      );
    }());
  }

  void addItem({
    required MenuItem item,
    required PizzaSize size,
    required PizzaCrust crust,
    required List<ToppingOption> toppings,
    int quantity = 1,
    String? instructions,
  }) {
    final cartItemId = CartItem.lineIdentity(
      item.id,
      size,
      crust,
      toppings,
    );

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
    _recordChange();
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
    _recordChange();
  }

  void removeItem(String cartItemId) {
    state = state.copyWith(
      items: state.items.where((item) => item.id != cartItemId).toList(),
    );
    _recordChange();
  }

  void clearCart() {
    state = _empty;
    _recordChange();
  }

  /// Replaces the whole line list with [items], keeping each line's own
  /// identity. Checkout-time revalidation needs this rather than re-adding:
  /// the saved cart must come out the other side exactly once, neither merged
  /// with itself nor doubled.
  void replaceCartItems(List<CartItem> items) {
    state = state.copyWith(items: items);
    _recordChange();
  }

  void _recordChange() {
    _changedSinceBoot = true;
    _persist();
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});
