import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/menu/models/menu_item.dart';
import 'package:mrpizza/features/menu/providers/menu_provider.dart';
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
        branchesFutureProvider.overrideWith((ref) async => [
          const Branch(
            id: 'branch-1',
            name: 'Downtown',
          ),
        ]),
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
}
