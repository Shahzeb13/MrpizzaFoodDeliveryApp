import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/menu/models/menu_item.dart';
import 'package:mrpizza/features/menu/providers/menu_provider.dart';
import 'package:mrpizza/features/orders/data/orders_repository.dart';
import 'package:mrpizza/features/orders/models/branch.dart';
import 'package:mrpizza/features/orders/providers/orders_provider.dart';
import 'package:mrpizza/features/payment/screens/checkout_screen.dart';
import 'package:mrpizza/features/profile/models/profile.dart';
import 'package:mrpizza/features/profile/providers/profile_provider.dart';

void main() {
  testWidgets('CheckoutScreen renders items in cart without crashing', (tester) async {
    const testItem = MenuItem(
      id: 'item-1',
      title: 'Margherita Pizza',
      description: 'Classic cheese and tomato',
      basePrice: 1200,
      imageUrl: 'https://example.com/pizza.jpg',
      category: ItemCategory.classics,
      rating: 4.8,
    );

    final container = ProviderContainer(
      overrides: [
        addressesFutureProvider.overrideWith((ref) async => [
          const UserAddress(
            id: 'addr-1',
            userId: 'user-1',
            label: 'Home',
            addressLine: '123 Test Street',
            isDefault: true,
          ),
        ]),
        branchesFutureProvider.overrideWith(
          (ref) async => const BranchCatalog(
            branches: [Branch(id: 'branch-1', name: 'Downtown')],
            usedFallbackData: false,
          ),
        ),
      ],
    );

    // Add item to cart
    container.read(cartProvider.notifier).addItem(
      item: testItem,
      size: PizzaSize.medium,
      crust: PizzaCrust.thin,
      toppings: const [],
      quantity: 1,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: CheckoutScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Your Cart & Checkout'), findsOneWidget);
    expect(find.text('Order Items'), findsOneWidget);
    expect(find.text('Margherita Pizza'), findsOneWidget);
  });

  group('branch label honesty', () {
    const abbottabad = Branch(
      id: 'branch-abbottabad',
      name: 'Abbottabad',
      latitude: 34.204008,
      longitude: 73.238723,
    );
    const mansehra = Branch(
      id: 'branch-mansehra',
      name: 'Mansehra',
      latitude: 34.328686,
      longitude: 73.199313,
    );

    Future<ProviderContainer> pumpCheckout(
      WidgetTester tester, {
      required UserAddress address,
      Branch? manuallyChosenBranch,
    }) async {
      final container = ProviderContainer(
        overrides: [
          addressesFutureProvider.overrideWith((ref) async => [address]),
          branchesFutureProvider.overrideWith(
            (ref) async => const BranchCatalog(
              branches: [abbottabad, mansehra],
              usedFallbackData: false,
            ),
          ),
        ],
      );

      container.read(cartProvider.notifier).addItem(
            item: const MenuItem(
              id: 'item-1',
              title: 'Margherita Pizza',
              description: 'Classic cheese and tomato',
              basePrice: 1200,
              imageUrl: 'https://example.com/pizza.jpg',
              category: ItemCategory.classics,
              rating: 4.8,
            ),
            size: PizzaSize.medium,
            crust: PizzaCrust.thin,
            toppings: const [],
            quantity: 1,
          );

      final notifier = container.read(checkoutProvider.notifier);
      notifier.selectAddress(address, branches: [abbottabad, mansehra]);
      if (manuallyChosenBranch != null) {
        notifier.selectBranch(manuallyChosenBranch);
      }

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: CheckoutScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      return container;
    }

    testWidgets('says nearest when the branch was proven closest', (tester) async {
      await pumpCheckout(
        tester,
        address: const UserAddress(
          id: 'addr-1',
          userId: 'user-1',
          label: 'Home',
          addressLine: 'Al Mansoor Town, Abbottabad',
          latitude: 34.2045,
          longitude: 73.2400,
          isDefault: true,
        ),
      );

      expect(
        find.textContaining('Delivering from Abbottabad (nearest branch)'),
        findsOneWidget,
      );
    });

    testWidgets('does not say nearest for a hand-picked branch', (tester) async {
      await pumpCheckout(
        tester,
        address: const UserAddress(
          id: 'addr-2',
          userId: 'user-1',
          label: 'Unpinned',
          addressLine: 'Somewhere without coordinates',
        ),
        manuallyChosenBranch: mansehra,
      );

      expect(find.textContaining('Delivering from Mansehra'), findsOneWidget);
      expect(find.textContaining('nearest'), findsNothing);
    });
  });
}
