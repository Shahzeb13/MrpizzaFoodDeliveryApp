import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../menu/providers/menu_provider.dart';
import '../../orders/models/branch.dart';
import '../../orders/models/order.dart';
import '../../orders/providers/orders_provider.dart';
import '../../profile/models/profile.dart';
import '../../profile/providers/profile_provider.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _isPlacingOrder = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncCheckout();
    });
  }

  /// Applies the sensible defaults once the address/branch data is available:
  /// - Delivery: default address + nearer branch.
  /// - Pickup: first branch (only when nothing pre-selected yet).
  void _syncCheckout() {
    final addresses = ref.read(addressesFutureProvider).value ?? const [];
    final branches = ref.read(branchesFutureProvider).value ?? const [];
    final notifier = ref.read(checkoutProvider.notifier);
    final checkout = ref.read(checkoutProvider);

    if (checkout.orderType == OrderType.pickup) {
      if (checkout.branch == null && branches.isNotEmpty) {
        notifier.selectBranch(branches.first);
      }
      return;
    }

    if (addresses.isEmpty) return;

    if (checkout.address != null && checkout.branch == null && branches.isNotEmpty) {
      notifier.selectAddress(checkout.address!, branches: branches);
    } else if (checkout.address == null) {
      notifier.selectDeliveryDefault(addresses: addresses, branches: branches);
    }
  }

  void _setOrderType(OrderType type) {
    final addresses = ref.read(addressesFutureProvider).value ?? const [];
    final branches = ref.read(branchesFutureProvider).value ?? const [];
    final notifier = ref.read(checkoutProvider.notifier);

    if (type == OrderType.pickup) {
      notifier.selectPickup(branches: branches);
    } else {
      notifier.selectDeliveryDefault(addresses: addresses, branches: branches);
    }
  }

  void _showAddressPicker(List<UserAddress> addresses) {
    final branches = ref.read(branchesFutureProvider).value ?? const [];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final selectedId = ref.read(checkoutProvider).address?.id;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Select Delivery Address',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: addresses.map((address) {
                      final isSelected = address.id == selectedId;
                      return InkWell(
                        onTap: () {
                          ref
                              .read(checkoutProvider.notifier)
                              .selectAddress(address, branches: branches);
                          Navigator.pop(sheetContext);
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.border,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.location_on_rounded,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      address.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      address.addressLine,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle,
                                  color: AppColors.primary,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmOrder({
    required CartState cart,
    required CheckoutState checkout,
  }) async {
    if (_isPlacingOrder) return;

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    final branch = checkout.branch;
    if (branch == null) {
      _showMessage('Please select a branch first.');
      return;
    }
    if (checkout.isDelivery && checkout.address == null) {
      _showMessage('Please select a delivery address.');
      return;
    }

    setState(() => _isPlacingOrder = true);
    try {
      final totals =
          OrderTotals(subtotal: cart.subtotal, orderType: checkout.orderType);
      final order = Order(
        customerId: userId,
        branchId: branch.id,
        addressId: checkout.isDelivery ? checkout.address!.id : null,
        orderType: checkout.orderType,
        totals: totals,
        items: cart.items
            .map(
              (ci) => OrderItem(
                menuItemId: ci.item.id,
                quantity: ci.quantity,
                unitPrice: ci.unitPrice,
              ),
            )
            .toList(),
      );
      await ref.read(ordersRepositoryProvider).placeOrder(order);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPlacingOrder = false);
      _showMessage(
        'Failed to place order. Please try again.',
        isError: true,
      );
      return;
    }

    ref.read(cartProvider.notifier).clearCart();
    if (!mounted) return;
    _showMessage(
      checkout.isDelivery ? 'Order confirmed! It is on its way.' : 'Order confirmed! Ready for pickup.',
    );
    context.go('/home');
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final addressesAsync = ref.watch(addressesFutureProvider);
    final branchesAsync = ref.watch(branchesFutureProvider);
    final checkout = ref.watch(checkoutProvider);

    ref.listen(addressesFutureProvider, (previous, next) => _syncCheckout());
    ref.listen(branchesFutureProvider, (previous, next) => _syncCheckout());

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Your Cart & Checkout',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (cart.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: () {
                ref.read(cartProvider.notifier).clearCart();
              },
            ),
        ],
      ),
      body: cart.items.isEmpty ? _buildEmptyState() : _buildCheckout(cart, checkout, addressesAsync, branchesAsync),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.local_pizza_rounded,
            size: 64,
            color: AppColors.textLight,
          ),
          const SizedBox(height: 16),
          const Text(
            'Your Cart is Empty',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Explore our menu and add your favorite pizzas!',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              context.go('/home');
            },
            child: const Text('Explore Menu'),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckout(
    CartState cart,
    CheckoutState checkout,
    AsyncValue<List<UserAddress>> addressesAsync,
    AsyncValue<List<Branch>> branchesAsync,
  ) {
    final totals = OrderTotals(subtotal: cart.subtotal, orderType: checkout.orderType);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildItemsSection(cart),
          const SizedBox(height: 20),
          _buildOrderTypeSection(checkout),
          const SizedBox(height: 20),
          if (checkout.isDelivery)
            ..._buildDeliverySection(addressesAsync, checkout)
          else
            ..._buildPickupSection(branchesAsync, checkout),
          const SizedBox(height: 20),
          _buildSummarySection(checkout, totals),
          const SizedBox(height: 30),
          _buildConfirmButton(checkout, totals),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildItemsSection(CartState cart) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Order Items',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'Subtotal: Rs. ${cart.subtotal.toInt()}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...cart.items.map((cartItem) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    cartItem.item.imageUrl,
                    width: 62,
                    height: 62,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 62,
                        height: 62,
                        color: AppColors.background,
                        child: const Center(
                          child: Icon(
                            Icons.local_pizza_rounded,
                            color: AppColors.textLight,
                            size: 28,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              cartItem.item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                              color: Colors.redAccent,
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: 'Remove',
                            onPressed: () {
                              ref
                                  .read(cartProvider.notifier)
                                  .removeItem(cartItem.id);
                            },
                          ),
                        ],
                      ),
                      Text(
                        '${cartItem.size.name} • ${cartItem.crust.name}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (cartItem.selectedToppings.isNotEmpty)
                        Text(
                          'Toppings: ${cartItem.selectedToppings.map((t) => t.name).join(', ')}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        'Rs. ${cartItem.totalPrice.toInt()}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, size: 16),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          ref
                              .read(cartProvider.notifier)
                              .updateQuantity(cartItem.id, -1);
                        },
                      ),
                      Text(
                        '${cartItem.quantity}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 16),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          ref
                              .read(cartProvider.notifier)
                              .updateQuantity(cartItem.id, 1);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildOrderTypeSection(CheckoutState checkout) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Delivery or Pickup',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<OrderType>(
            segments: const [
              ButtonSegment(
                value: OrderType.delivery,
                label: Text('Delivery'),
                icon: Icon(Icons.delivery_dining_rounded, size: 18),
              ),
              ButtonSegment(
                value: OrderType.pickup,
                label: Text('Pickup'),
                icon: Icon(Icons.storefront_rounded, size: 18),
              ),
            ],
            selected: {checkout.orderType},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              _setOrderType(selection.first);
            },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.primary
                    : Colors.white,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : AppColors.textSecondary,
              ),
              side: const WidgetStatePropertyAll(
                BorderSide(color: AppColors.border),
              ),
              textStyle: const WidgetStatePropertyAll(
                TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              iconColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildDeliverySection(
    AsyncValue<List<UserAddress>> addressesAsync,
    CheckoutState checkout,
  ) {
    if (addressesAsync.isLoading) {
      return [_sectionTitle('Delivery Details'), const SizedBox(height: 12), _loadingBox()];
    }
    if (addressesAsync.hasError) {
      return [
        _sectionTitle('Delivery Details'),
        const SizedBox(height: 12),
        _errorBox(() => ref.invalidate(addressesFutureProvider)),
      ];
    }

    final addresses = addressesAsync.value ?? const <UserAddress>[];
    if (addresses.isEmpty) {
      return [
        _sectionTitle('Delivery Details'),
        const SizedBox(height: 12),
        _noAddressesCard(),
      ];
    }
    return [
      _sectionTitle('Delivery Details'),
      const SizedBox(height: 12),
      _deliveryAddressCard(addresses, checkout),
      if (checkout.branch != null) ...[
        const SizedBox(height: 12),
        _branchNote(checkout),
      ],
    ];
  }

  Widget _deliveryAddressCard(List<UserAddress> addresses, CheckoutState checkout) {
    final address = checkout.address ?? addresses.firstWhere((a) => a.isDefault, orElse: () => addresses.first);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _showAddressPicker(addresses),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.location_on, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    address.label,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address.addressLine,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Text(
              'Change',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }

  Widget _branchNote(CheckoutState checkout) {
    final branch = checkout.branch!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Delivering from ${branch.name} (nearest branch)',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noAddressesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.location_off_rounded, color: AppColors.textLight),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No saved addresses yet. Add one to place a delivery order.',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/addresses'),
              icon: const Icon(Icons.add_location_alt_rounded, size: 18),
              label: const Text('Add Address'),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPickupSection(
    AsyncValue<List<Branch>> branchesAsync,
    CheckoutState checkout,
  ) {
    return [
      _sectionTitle('Choose Pickup Branch'),
      const SizedBox(height: 12),
      branchesAsync.when(
        loading: () => _loadingBox(),
        error: (error, _) => _errorBox(() => ref.invalidate(branchesFutureProvider)),
        data: (branches) {
          if (branches.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No branches available right now.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          return Column(
            children: branches.map((branch) {
              final isSelected = checkout.branch?.id == branch.id;
              return InkWell(
                onTap: () {
                  ref.read(checkoutProvider.notifier).selectBranch(branch);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withOpacity(0.05)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textLight,
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          isSelected
                              ? Icons.storefront_rounded
                              : Icons.storefront_outlined,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            branch.name,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    ];
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  Widget _loadingBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }

  Widget _errorBox(VoidCallback onRetry) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Text(
            'Could not load data',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildSummarySection(
    CheckoutState checkout,
    OrderTotals totals,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Order Summary',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              _summaryRow('Subtotal', 'Rs. ${totals.subtotal.toInt()}'),
              const SizedBox(height: 8),
              _summaryRow(
                'Estimated Tax (8%)',
                'Rs. ${totals.tax.toInt()}',
              ),
              const SizedBox(height: 8),
              _summaryRow(
                'Delivery Charge',
                'Rs. ${totals.deliveryFee.toInt()}',
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Amount',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Rs. ${totals.total.toInt()}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildConfirmButton(
    CheckoutState checkout,
    OrderTotals totals,
  ) {
    final canPlace = !_isPlacingOrder && checkout.branch != null;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: canPlace
            ? () => _confirmOrder(cart: ref.read(cartProvider), checkout: checkout)
            : checkout.branch == null
                ? () => _showMessage(checkout.isDelivery ? 'Select a delivery address first.' : 'Select a pickup branch first.')
                : null,
        child: _isPlacingOrder
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(
                'Confirm Order • Rs. ${totals.total.toInt()}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}