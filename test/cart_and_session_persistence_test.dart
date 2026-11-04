import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/location_provider.dart';
import 'package:mrpizza/core/storage/local_storage.dart';
import 'package:mrpizza/features/location/data/location_repository.dart';
import 'package:mrpizza/features/location/models/captured_location.dart';
import 'package:mrpizza/features/menu/data/cart_revalidation.dart' as revalidation;
import 'package:mrpizza/features/menu/models/menu_item.dart';
import 'package:mrpizza/features/menu/providers/menu_provider.dart';
import 'package:mrpizza/features/orders/models/branch.dart';
import 'package:mrpizza/features/orders/models/order.dart';
import 'package:mrpizza/features/orders/providers/orders_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _itemAId = '00000000-0000-0000-0000-000000000001';
const _itemBId = '00000000-0000-0000-0000-000000000002';

MenuItem _item({
  String id = _itemAId,
  String title = 'Chicken Tikka',
  double basePrice = 500,
}) {
  return MenuItem(
    id: id,
    title: title,
    description: 'Grilled to order',
    basePrice: basePrice,
    imageUrl: 'https://example.com/$id.png',
    categoryName: 'Pizza',
  );
}

CartItem _line({
  String id = _itemAId,
  MenuItem? item,
  PizzaSize size = PizzaSize.medium,
  PizzaCrust crust = PizzaCrust.thin,
  List<ToppingOption> toppings = const [],
  int quantity = 2,
}) {
  return CartItem(
    id: CartItem.lineIdentity(id, size, crust, toppings),
    item: item ?? _item(id: id),
    size: size,
    crust: crust,
    selectedToppings: toppings,
    quantity: quantity,
  );
}

/// Prime the store as if the previous run left [value] behind (null forgets).
Future<void> _seed(String key, String? value) async {
  final prefs = await SharedPreferences.getInstance();
  if (value == null) {
    await prefs.remove(key);
  } else {
    await prefs.setString(key, value);
  }
}

/// A fresh store for this test, the way a restart looks to the app.
Future<void> _forgetStoredSession() async {
  LocalStore.resetForTest();
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('the cart survives an app restart', () {
    test('a saved cart is restored line by line', () async {
      await _forgetStoredSession();
      await _seed(
        localStorageCartKey,
        CartState.toStorageJson(
          [
            _line(
              toppings: [
                const ToppingOption(
                    name: 'Extra Cheese', price: 80, icon: 'x'),
              ],
            ),
          ],
        ),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider);
      await pumpEventQueue();

      final cart = container.read(cartProvider);
      expect(cart.items, hasLength(1));
      expect(cart.items.single.quantity, 2);
      expect(cart.items.single.item.title, 'Chicken Tikka');
      expect(cart.items.single.size, PizzaSize.medium);
      expect(cart.items.single.crust, PizzaCrust.thin);
      expect(cart.items.single.selectedToppings.single.name, 'Extra Cheese');
      expect(cart.subtotal, closeTo((500 * 1.35 + 80) * 2, 0.001));
    });

    test('a change made now is what the next run reads back', () async {
      await _forgetStoredSession();

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider.notifier).addItem(
            item: _item(),
            size: PizzaSize.large,
            crust: PizzaCrust.stuffed,
            toppings: [
              const ToppingOption(name: 'Olives', price: 60, icon: 'o'),
            ],
            quantity: 1,
          );
      await pumpEventQueue();
      expect(container.read(cartProvider).items, hasLength(1));

      // The restart: the same store, read by a fresh notifier. If the write
      // above never landed, this read comes back empty.
      LocalStore.resetForTest();
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);

      restarted.read(cartProvider);
      await pumpEventQueue();

      final restored = restarted.read(cartProvider);
      expect(restored.items, hasLength(1));
      expect(restored.items.single.size, PizzaSize.large);
      expect(restored.items.single.crust, PizzaCrust.stuffed);

      // The restored line must still merge with the same order from the sheet.
      restarted.read(cartProvider.notifier).addItem(
            item: _item(),
            size: PizzaSize.large,
            crust: PizzaCrust.stuffed,
            toppings: [
              const ToppingOption(name: 'Olives', price: 60, icon: 'o'),
            ],
          );
      expect(restarted.read(cartProvider).items.single.quantity, 2);
    });

    test('clearing the cart forgets what was saved', () async {
      await _forgetStoredSession();
      await _seed(localStorageCartKey, CartState.toStorageJson([_line()])!);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider);
      await pumpEventQueue();
      expect(container.read(cartProvider).items, isNotEmpty);

      container.read(cartProvider.notifier).clearCart();
      await pumpEventQueue();

      LocalStore.resetForTest();
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);

      restarted.read(cartProvider);
      await pumpEventQueue();
      expect(restarted.read(cartProvider).items, isEmpty);
    });

    test('junk in storage empties the cart instead of crashing', () async {
      await _forgetStoredSession();
      await _seed(localStorageCartKey, 'not json at all');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider);
      await pumpEventQueue();

      expect(container.read(cartProvider).items, isEmpty);
    });

    test('a line with an unknown size is dropped, nothing leaks back', () async {
      final stored = CartState.toStorageJson([_line()])!;
      // Corrupt the size the way a renamed enum constant would.
      await _forgetStoredSession();
      await _seed(
        localStorageCartKey,
        stored.replaceFirst('"PizzaSize.medium"', '"PizzaSize.jumbo"'),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(cartProvider);
      await pumpEventQueue();

      expect(container.read(cartProvider).items, isEmpty);
    });
  });

  group('the delivery address survives an app restart', () {
    test('a stored pin and address are restored', () async {
      await _forgetStoredSession();
      await _seed(
        localStorageLocationKey,
        jsonEncode(
            {'address': 'House 5, Abbottabad', 'latitude': 34.15, 'longitude': 73.22}),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(locationProvider);
      await pumpEventQueue();

      final restored = container.read(locationProvider);
      expect(restored.isSet, isTrue);
      expect(restored.address, 'House 5, Abbottabad');
      expect(restored.latitude, 34.15);
      expect(restored.longitude, 73.22);
    });

    test('a pin chosen now is what the next run reads back', () async {
      await _forgetStoredSession();

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(locationProvider.notifier).applyMapPick(
            latitude: 34.17,
            longitude: 73.25,
            addressText: 'Triple One Hotel',
          );
      await pumpEventQueue();

      LocalStore.resetForTest();
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);

      restarted.read(locationProvider);
      await pumpEventQueue();

      final restored = restarted.read(locationProvider);
      expect(restored.address, 'Triple One Hotel');
      expect(restored.latitude, 34.17);
      expect(restored.longitude, 73.25);
    });

    test('a failed GPS capture erases nothing that was stored', () async {
      await _forgetStoredSession();
      await _seed(
        localStorageLocationKey,
        jsonEncode(
            {'address': 'House 5, Abbottabad', 'latitude': 34.15, 'longitude': 73.22}),
      );

      final container = ProviderContainer(
        overrides: [
          locationRepositoryProvider.overrideWithValue(
            const LocationRepository(
              deviceSource: _PermissionDeniedSource(),
              addressLookup: _SilentAddressLookup(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(locationProvider);
      await pumpEventQueue();
      expect(container.read(locationProvider).address, 'House 5, Abbottabad');

      await container.read(locationProvider.notifier).useCurrentLocation();
      await pumpEventQueue();

      expect(container.read(locationProvider).errorMessage, isNotNull);

      // The restart still lands the customer back on their address, even
      // though the last capture attempt failed.
      LocalStore.resetForTest();
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);

      restarted.read(locationProvider);
      await pumpEventQueue();
      expect(
        restarted.read(locationProvider).address,
        'House 5, Abbottabad',
      );
    });

    test('typing an empty address forgets the stored one', () async {
      await _forgetStoredSession();
      await _seed(
        localStorageLocationKey,
        jsonEncode(
            {'address': 'House 5, Abbottabad', 'latitude': 34.15, 'longitude': 73.22}),
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(locationProvider);
      await pumpEventQueue();

      await container.read(locationProvider.notifier).setLocation('');
      await pumpEventQueue();

      LocalStore.resetForTest();
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);

      restarted.read(locationProvider);
      await pumpEventQueue();

      expect(restarted.read(locationProvider).isSet, isFalse);
    });
  });

  group('the checkout choice survives an app restart', () {
    test('pickup is remembered and re-applied', () async {
      await _forgetStoredSession();

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(checkoutProvider.notifier)
          .selectPickup(branches: const [Branch(id: 'b-abb', name: 'Abbottabad')]);
      await pumpEventQueue();
      expect(container.read(checkoutProvider).orderType, OrderType.pickup);

      LocalStore.resetForTest();
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);

      restarted.read(checkoutProvider);
      await pumpEventQueue();

      expect(restarted.read(checkoutProvider).orderType, OrderType.pickup);
    });

    test('a hand-picked branch is remembered, an automatic one is not',
        () async {
      await _forgetStoredSession();
      const abbottabad = Branch(id: 'b-abb', name: 'Abbottabad');
      const mansehra = Branch(id: 'b-mansehra', name: 'Mansehra');

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(checkoutProvider.notifier)
          .selectBranchAutomatically(abbottabad);
      await pumpEventQueue();
      expect(CheckoutNotifier.rememberedManualBranchId(), isNull);

      container.read(checkoutProvider.notifier).selectBranch(mansehra);
      await pumpEventQueue();
      expect(CheckoutNotifier.rememberedManualBranchId(), 'b-mansehra');

      LocalStore.resetForTest();
      final restarted = ProviderContainer();
      addTearDown(restarted.dispose);

      restarted.read(checkoutProvider);
      await pumpEventQueue();
      expect(CheckoutNotifier.rememberedManualBranchId(), 'b-mansehra');
    });
  });

  group('checkout revalidation against the live menu', () {
    test('unavailable items are removed', () {
      final result = revalidation.revalidateCartAgainstMenu(
        items: [
          _line(id: _itemAId, quantity: 2),
          _line(id: _itemBId, quantity: 1),
        ],
        availableItems: {
          _itemAId: _item(),
        },
      );

      expect(result.adjustedItems, hasLength(1));
      expect(result.adjustedItems.single.quantity, 2);
      expect(result.removedCount, 1);
      expect(result.repricedCount, 0);
      expect(result.hasChanges, isTrue);
    });

    test('repriced items keep their line at today’s price', () {
      final result = revalidation.revalidateCartAgainstMenu(
        items: [_line()],
        availableItems: {
          _itemAId: _item(basePrice: 650),
        },
      );

      expect(result.adjustedItems, hasLength(1));
      // 650 * 1.35 (medium) stays; nothing else about the line moved.
      expect(result.adjustedItems.single.item.basePrice, 650);
      expect(result.adjustedItems.single.quantity, 2);
      expect(result.repricedCount, 1);
      expect(result.removedCount, 0);
    });

    test('a stable menu changes nothing', () {
      final result = revalidation.revalidateCartAgainstMenu(
        items: [_line()],
        availableItems: {_itemAId: _item()},
      );

      expect(result.hasChanges, isFalse);
      expect(result.adjustedItems.single.id, _line().id);
    });

    test('the message names what happened', () {
      const removedOnly = revalidation.CartRevalidationResult(
        adjustedItems: [],
        removedCount: 1,
        repricedCount: 0,
      );
      const repricedOnly = revalidation.CartRevalidationResult(
        adjustedItems: [],
        removedCount: 0,
        repricedCount: 2,
      );
      const both = revalidation.CartRevalidationResult(
        adjustedItems: [],
        removedCount: 1,
        repricedCount: 1,
      );
      const quiet = revalidation.CartRevalidationResult(
        adjustedItems: [],
        removedCount: 0,
        repricedCount: 0,
      );

      expect(revalidation.cartRevalidationMessage(removedOnly), isNotNull);
      expect(revalidation.cartRevalidationMessage(repricedOnly), isNotNull);
      expect(revalidation.cartRevalidationMessage(both), isNotNull);
      expect(revalidation.cartRevalidationMessage(quiet), isNull);
    });
  });
}

class _PermissionDeniedSource implements DeviceLocationSource {
  const _PermissionDeniedSource();

  @override
  Future<LocationPermissionOutcome> ensurePermission() async =>
      LocationPermissionOutcome.deniedForever;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<CapturedCoordinates> readCurrentCoordinates() async {
    throw const LocationCaptureException('denied in test');
  }
}

class _SilentAddressLookup implements AddressTextLookup {
  const _SilentAddressLookup();

  @override
  Future<String?> lookupAddressText(CapturedCoordinates coordinates) async =>
      null;
}
