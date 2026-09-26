import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/location_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/widgets.dart';
import '../../menu/providers/menu_provider.dart';
import '../../orders/data/orders_repository.dart';
import '../../orders/models/branch.dart';
import '../../orders/models/order.dart';
import '../../orders/providers/orders_provider.dart';
import '../../profile/models/profile.dart';
import '../../profile/providers/address_selection_provider.dart';
import '../../profile/providers/profile_provider.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _isPlacingOrder = false;

  /// The branches currently loaded, or an empty list before the first load.
  /// Empty (not bundled) on purpose: inventing branches here would let an
  /// order be placed against a branch id that does not exist in the database.
  List<Branch> get _loadedBranches =>
      ref.read(branchesFutureProvider).value?.branches ?? const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncCheckout();
    });
  }

  /// Applies the sensible defaults once the address/branch data is available:
  /// - The map pin picked on the home screen decides the branch, because it is
  ///   a position the customer actually chose.
  /// - Delivery: default address + nearer branch.
  /// - Pickup: first branch (only when nothing pre-selected yet).
  void _syncCheckout() {
    final addresses = ref.read(addressesFutureProvider).value ?? const [];
    final branches = _loadedBranches;
    final notifier = ref.read(checkoutProvider.notifier);
    final pin = ref.read(locationProvider);

    // The pin is the strongest signal available and needs no saved address row,
    // so it goes first. A hand-picked branch is left alone by this call.
    if (pin.hasCoordinates && branches.isNotEmpty) {
      notifier.syncBranchFromPin(
        latitude: pin.latitude,
        longitude: pin.longitude,
        branches: branches,
      );
    }

    final checkout = ref.read(checkoutProvider);

    if (checkout.orderType == OrderType.pickup) {
      if (checkout.branch == null && branches.isNotEmpty) {
        notifier.selectBranchAutomatically(branches.first);
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
    final branches = _loadedBranches;
    final notifier = ref.read(checkoutProvider.notifier);
    final pin = ref.read(locationProvider);

    if (type == OrderType.pickup) {
      notifier.selectPickup(branches: branches);
    } else {
      notifier.selectDeliveryDefault(addresses: addresses, branches: branches);
    }

    if (pin.hasCoordinates && branches.isNotEmpty) {
      notifier.syncBranchFromPin(
        latitude: pin.latitude,
        longitude: pin.longitude,
        branches: branches,
      );
    }
  }

  /// "Use where I am now" row at the top of the address picker.
  ///
  /// Tapping it captures the position, stores it, and applies it to the order in
  /// one go, so the customer never has to open a form to say where they are.
  Widget _buildCurrentLocationRow(
    BuildContext sheetContext,
    LocationState location,
    List<Branch> branches,
  ) {
    final hasPin = location.hasCoordinates;
    final isSelected = hasPin && ref.read(checkoutProvider).address == null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          if (!hasPin) {
            await ref.read(locationProvider.notifier).useCurrentLocation();
            if (!mounted) return;
            final captured = ref.read(locationProvider);
            final failure = captured.errorMessage;
            if (failure != null) {
              _showMessage(failure, isError: true);
              return;
            }
          }

          // Store it, then select the stored address. Persisting first means the
          // order references a real address row and the choice is remembered.
          SaveLocationResult? saved;
          try {
            saved = await ref.read(saveCurrentLocationProvider)();
          } catch (_) {
            // Fall back to the raw pin so checkout is never blocked by a
            // storage failure.
          }

          if (!mounted) return;
          if (saved != null) {
            ref
                .read(checkoutProvider.notifier)
                .selectAddress(saved.address, branches: branches);
          } else if (hasPin) {
            ref.read(checkoutProvider.notifier).syncBranchFromPin(
                  latitude: location.latitude,
                  longitude: location.longitude,
                  branches: branches,
                );
          }

          if (!mounted) return;
          // The sheet's own context can be torn down independently of this State,
          // so it gets its own mounted check before being used.
          if (!sheetContext.mounted) return;
          Navigator.of(sheetContext).pop();
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primaryTint,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.primaryLight,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              const MrIconWell(
                icon: Icons.my_location_rounded,
                size: 18,
                color: AppColors.primary,
                background: AppColors.surface,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Use my current location',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasPin
                          ? (location.address.isEmpty
                              ? 'Pinned on the map'
                              : location.address)
                          : 'Tap to drop a pin and save it',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Lets the customer choose where the order goes: their current position as
  /// one tap, or any of the addresses already on file.
  void _showAddressPicker(List<UserAddress> addresses) {
    final branches = _loadedBranches;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        final selectedId = ref.read(checkoutProvider).address?.id;
        final location = ref.watch(locationProvider);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.borderDeep,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text(
                  'Deliver To',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              // Where you are right now, offered as one tap. Choosing it stores
              // the location, so it also joins the saved list below.
              _buildCurrentLocationRow(sheetContext, location, branches),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Text(
                  addresses.isEmpty
                      ? 'No saved addresses yet'
                      : 'SAVED ADDRESSES',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.textLight,
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
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.border,
                              width: isSelected ? 1.5 : 1,
                            ),
                            boxShadow: isSelected
                                ? null
                                : const [
                                    BoxShadow(
                                      color: AppColors.shadowSoft,
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: Row(
                            children: [
                              MrIconWell(
                                icon: Icons.location_on_rounded,
                                size: 18,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textPrimary,
                                background: isSelected
                                    ? AppColors.primaryTint
                                    : AppColors.sand,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      address.label,
                                      style: const TextStyle(
                                        fontFamily: AppTheme.fontFamily,
                                        fontWeight: FontWeight.w800,
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
                                  Icons.check_circle_rounded,
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

  /// Returns the branch this order should be placed against, or null when the
  /// customer still has to choose and the order must not be placed yet.
  ///
  /// `orders.branch_id` is NOT NULL, so an order cannot exist without a branch.
  /// There is therefore no path here that leaves the customer stuck: the pin and
  /// the saved address are both tried first, a single-branch restaurant is
  /// routed automatically, and only a genuine choice between several branches
  /// asks the customer.
  Branch? _resolveBranchOrAskCustomer(CheckoutState checkout) {
    if (checkout.branch == null) {
      _syncCheckout();
      checkout = ref.read(checkoutProvider);
    }

    final resolved = checkout.branch;
    if (resolved != null) return resolved;

    final branches = _loadedBranches;
    if (branches.isEmpty) {
      _showMessage('No branches are available right now.', isError: true);
      return null;
    }
    if (branches.length == 1) {
      ref
          .read(checkoutProvider.notifier)
          .selectBranchAutomatically(branches.first);
      return ref.read(checkoutProvider).branch ?? branches.first;
    }

    _showBranchPickerSheet(branches);
    return null;
  }

  /// Asks which branch to use when none could be worked out from the customer's
  /// position. Never leaves the order in a failed state — the customer taps a
  /// branch and confirms again.
  void _showBranchPickerSheet(List<Branch> branches) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose your branch',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'We could not work out the closest branch from your location.',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                ...branches.map(
                  (branch) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        ref.read(checkoutProvider.notifier).selectBranch(branch);
                        Navigator.pop(sheetContext);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.storefront_rounded,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              branch.name,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
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

    final branch = _resolveBranchOrAskCustomer(checkout);
    if (branch == null) return;
    final resolvedCheckout = ref.read(checkoutProvider);

    if (resolvedCheckout.isDelivery && resolvedCheckout.address == null) {
      _showMessage('Please select a delivery address.');
      return;
    }

    setState(() => _isPlacingOrder = true);
    final totals = OrderTotals(subtotal: cart.subtotal, orderType: resolvedCheckout.orderType);
    try {
      final order = Order(
        customerId: userId,
        branchId: branch.id,
        addressId: resolvedCheckout.isDelivery ? resolvedCheckout.address!.id : null,
        orderType: resolvedCheckout.orderType,
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
      _showMessage(_orderErrorText(e), isError: true);
      return;
    }

    // Snapshot cart BEFORE clearing so the tracking screen can display items.
    ref.read(lastOrderSnapshotProvider.notifier).state = LastOrderSnapshot(
      items: List.unmodifiable(cart.items),
      totals: totals,
      orderType: resolvedCheckout.orderType,
    );

    ref.read(cartProvider.notifier).clearCart();
    if (!mounted) return;
    context.go('/orders/track');
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

  /// Translates low-level order-insert failures into actionable messages so
  /// the user sees WHY an order failed instead of a generic retry note.
  String _orderErrorText(Object error) {
    if (error is PostgrestException) {
      final code = error.code ?? '';
      final message = error.message.toLowerCase();
      if (code == '23503' ||
          message.contains('foreign key') ||
          message.contains('menu_item')) {
        return 'A cart item is no longer on the menu. '
            'Please remove it and place the order again.';
      }
      if (code == '23505' || message.contains('duplicate key')) {
        return 'This order was already placed. Please review your cart.';
      }
      if (code == '23514' || message.contains('check constraint')) {
        return 'Some order details are invalid. Please review and try again.';
      }
      return 'Failed to place order: ${error.message}';
    }
    return 'Failed to place order. Please check your connection and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final addressesAsync = ref.watch(addressesFutureProvider);
    final branchesAsync = ref.watch(branchesFutureProvider);
    final checkout = ref.watch(checkoutProvider);

    ref.listen(addressesFutureProvider, (previous, next) => _syncCheckout());
    ref.listen(branchesFutureProvider, (previous, next) => _syncCheckout());
    // A location picked on the home screen decides the branch, so the branch
    // has to be reworked out whenever that pin changes.
    ref.listen(locationProvider, (previous, next) => _syncCheckout());

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text(
          'Your Cart & Checkout',
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          if (cart.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.textPrimary),
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
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: AppColors.sand,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_pizza_rounded,
              size: 40,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Your Cart is Empty',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Explore our menu and add your favorite pizzas!',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            width: 200,
            child: FilledButton(
              onPressed: () {
                context.go('/home');
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 6,
                shadowColor: AppColors.primary.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Explore Menu',
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(width: 10),
                  Icon(Icons.arrow_forward_rounded, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckout(
    CartState cart,
    CheckoutState checkout,
    AsyncValue<List<UserAddress>> addressesAsync,
    AsyncValue<BranchCatalog> branchesAsync,
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
            ..._buildDeliverySection(addressesAsync, branchesAsync, checkout)
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
        MrSectionTitle(
          title: 'Order Items',
          trailing: Text(
            'Rs. ${cart.subtotal.toInt()}',
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const MrFadeDivider(),
        const SizedBox(height: 14),
        ...cart.items.map((cartItem) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadowSoft,
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.sand,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.all(5),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.network(
                      cartItem.item.imageUrl,
                      width: 58,
                      height: 58,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 58,
                          height: 58,
                          color: AppColors.sand,
                          child: const Center(
                            child: Text('🍕', style: TextStyle(fontSize: 26)),
                          ),
                        );
                      },
                    ),
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
                                fontFamily: AppTheme.fontFamily,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                              color: AppColors.textLight,
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
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (cartItem.selectedToppings.isNotEmpty)
                        Text(
                          'Toppings: ${cartItem.selectedToppings.map((t) => t.name).join(', ')}',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 11,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Text(
                        'Rs. ${cartItem.totalPrice.toInt()}',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontFamily,
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
                    color: AppColors.sand,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
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
                        style: const TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontWeight: FontWeight.w800,
                        ),
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
        const MrSectionTitle(title: 'Delivery or Pickup'),
        const SizedBox(height: 6),
        const MrFadeDivider(),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<OrderType>(
            segments: const [
              ButtonSegment(
                value: OrderType.delivery,
                label: Text(
                  'Delivery',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                icon: Icon(Icons.delivery_dining_rounded, size: 18),
              ),
              ButtonSegment(
                value: OrderType.pickup,
                label: Text(
                  'Pickup',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
                    : AppColors.surface,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.white
                    : AppColors.textSecondary,
              ),
              side: const WidgetStatePropertyAll(
                BorderSide(color: AppColors.borderDeep),
              ),
              textStyle: const WidgetStatePropertyAll(
                TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
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
    AsyncValue<BranchCatalog> branchesAsync,
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
      // The branch is worked out automatically, but the customer must still be
      // able to see it, and change it when the automatic pick is wrong.
      if (checkout.branch == null && branchesAsync.value != null) ...[
        const SizedBox(height: 12),
        _unresolvedBranchCard(),
      ],
    ];
  }

  /// Shown when no branch could be worked out. Tapping it opens the same picker
  /// Confirm Order uses, so the screen is never a dead end.
  Widget _unresolvedBranchCard() {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _showBranchPickerSheet(_loadedBranches),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primaryLight, width: 1.5),
        ),
        child: const Row(
          children: [
            MrIconWell(
              icon: Icons.storefront_rounded,
              size: 18,
              color: AppColors.primary,
              background: AppColors.surface,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Choose the branch that will cook your order',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.textLight),
          ],
        ),
      ),
    );
  }

  Widget _deliveryAddressCard(List<UserAddress> addresses, CheckoutState checkout) {
    final address = checkout.address ?? addresses.firstWhere((a) => a.isDefault, orElse: () => addresses.first);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _showAddressPicker(addresses),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowSoft,
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            const MrIconWell(
              icon: Icons.location_on_rounded,
              color: AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    address.label,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    address.addressLine,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Text(
              'Change',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
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
    // Only claim "nearest" when the branch was actually proven to be the
    // closest one to the delivery address.
    final label = checkout.branchIsNearest
        ? 'Delivering from ${branch.name} (nearest branch)'
        : 'Delivering from ${branch.name}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const MrIconWell(
            icon: Icons.storefront_rounded,
            size: 18,
            color: AppColors.primary,
            background: AppColors.surface,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w800,
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSoft,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
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
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
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
    AsyncValue<BranchCatalog> branchesAsync,
    CheckoutState checkout,
  ) {
    return [
      _sectionTitle('Choose Pickup Branch'),
      const SizedBox(height: 12),
      branchesAsync.when(
        loading: () => _loadingBox(),
        error: (error, _) => _errorBox(() => ref.invalidate(branchesFutureProvider)),
        data: (catalog) {
          final branches = catalog.branches;
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
                            ? AppColors.primaryTint
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryLight
                              : AppColors.border,
                          width: isSelected ? 1.5 : 1,
                        ),
                        boxShadow: isSelected
                            ? null
                            : const [
                                BoxShadow(
                                  color: AppColors.shadowSoft,
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
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
                            MrIconWell(
                              icon: isSelected
                                  ? Icons.storefront_rounded
                                  : Icons.storefront_outlined,
                              size: 18,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              background: isSelected
                                  ? AppColors.surface
                                  : AppColors.sand,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                branch.name,
                                style: TextStyle(
                                  fontFamily: AppTheme.fontFamily,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
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
      style: const TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    );
  }

  Widget _loadingBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSoft,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSoft,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Could not load data',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
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
        const MrSectionTitle(title: 'Order Summary'),
        const SizedBox(height: 6),
        const MrFadeDivider(),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowSoft,
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: MrFadeDivider(),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total Amount',
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Rs. ${totals.total.toInt()}',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
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
    // Button is enabled when:
    // - Delivery: an address is selected (branch auto-resolves from address)
    // - Pickup: a branch is selected
    // - Not already submitting
    final hasAddress = checkout.address != null;
    final hasBranch = checkout.branch != null;
    final canPlace = !_isPlacingOrder &&
        (checkout.isDelivery ? hasAddress || hasBranch : hasBranch);
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton(
        onPressed: canPlace
            ? () => _confirmOrder(
                cart: ref.read(cartProvider), checkout: checkout)
            : checkout.branch == null
                ? () => _showMessage(checkout.isDelivery
                    ? 'Select a delivery address first.'
                    : 'Select a pickup branch first.')
                : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 8,
          shadowColor: AppColors.primary.withValues(alpha: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: _isPlacingOrder
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Colors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Confirm Order',
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.primary,
                      size: 15,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Rs. ${totals.total.toInt()}',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}