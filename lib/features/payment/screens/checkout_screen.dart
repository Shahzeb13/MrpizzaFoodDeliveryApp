import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/location_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/widgets.dart';
import '../../../widgets/shared_components.dart';
import '../../auth/providers/auth_provider.dart';
import '../../location/screens/map_location_picker_sheet.dart';
import '../../menu/providers/menu_provider.dart';
import '../../loyalty/data/loyalty_repository.dart';
import '../../loyalty/models/loyalty.dart';
import '../../loyalty/providers/loyalty_provider.dart';
import '../../orders/data/orders_repository.dart';
import '../../orders/models/branch.dart';
import '../../orders/models/order.dart';
import '../../orders/providers/orders_provider.dart';
import '../../orders/providers/live_order_provider.dart';
import '../../orders/providers/order_tracking_provider.dart';
import '../../profile/models/profile.dart';
import '../../profile/providers/address_selection_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../data/payfast_checkout.dart';
import '../data/voucher_repository.dart';
import '../models/discount.dart';
import '../models/payment_choice.dart';
import '../providers/discount_provider.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _isPlacingOrder = false;

  /// Whether the blocking spinner is currently up.
  ///
  /// A flag rather than the `showDialog` future: dismissing means popping a
  /// route, and popping is only safe to do when this is true — otherwise a late
  /// dismiss would pop whichever screen happened to be on top instead.
  bool _processingOverlayOpen = false;

  /// The saving on this order — voucher, points, or the automatic welcome
  /// offer — held in a provider rather than in this screen's state.
  ///
  /// It cannot stay local any more: the controls that choose it moved to
  /// `/apply-discount`, so anything held here would be discarded the moment the
  /// customer came back from that page, and the order would go out at full
  /// price after they had been shown a saving.
  DiscountSelection get _selection => ref.read(discountSelectionProvider);

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

  /// Opens the delivery map and applies whatever the customer pins.
  ///
  /// The map is the only place a customer can see where a pin actually sits, so
  /// it is offered above the saved list. It stores the pick the same way a GPS
  /// capture is stored, which means it joins My Addresses and becomes
  /// selectable on later orders.
  Future<void> _pickLocationOnMap(List<Branch> branches) async {
    final picked = await showMapLocationPicker(context);
    if (!mounted || picked != true) return;

    // The sheet already stored the address; this only attaches it to the order
    // and lets the pin pick the branch.
    SaveLocationResult? saved;
    try {
      saved = await ref.read(saveCurrentLocationProvider)();
    } catch (_) {
      // A storage failure must not block the order; the pin still decides the
      // branch below.
    }
    if (!mounted) return;

    final address = saved?.address;
    if (address != null) {
      ref
          .read(checkoutProvider.notifier)
          .selectAddress(address, branches: branches);
      return;
    }

    final location = ref.read(locationProvider);
    if (location.hasCoordinates) {
      ref.read(checkoutProvider.notifier).syncBranchFromPin(
            latitude: location.latitude,
            longitude: location.longitude,
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
  /// one tap, a point chosen on the map, or any of the addresses already on
  /// file.
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    // The sheet is closed first so the map is not pushed on top
                    // of a modal the customer is meant to have finished with.
                    Navigator.of(sheetContext).pop();
                    await _pickLocationOnMap(branches);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Row(
                      children: [
                        MrIconWell(
                          icon: Icons.map_outlined,
                          size: 18,
                          color: AppColors.primary,
                          background: AppColors.sand,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pick on map',
                                style: TextStyle(
                                  fontFamily: AppTheme.fontFamily,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Move the map and drop the pin where you want it delivered',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textLight,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
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
                        ref
                            .read(checkoutProvider.notifier)
                            .selectBranch(branch);
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

  /// Opens `/payment-method` and places the order only if a method comes back.
  ///
  /// Pushing rather than going means the order is not written until the customer
  /// has actually chosen how to pay. Backing out of that page leaves nothing
  /// behind: no order row, no kitchen ticket, no voucher claimed against an
  /// order that was never placed.
  ///
  /// Loops because a customer who opens PayFast's page and then backs out has to
  /// be put straight back on the payment page with their cart intact, not
  /// stranded. Each pass places one order; the pass is only kept if it ends up
  /// paid, chosen as cash, or still awaiting a slow IPN.
  Future<void> _choosePaymentMethod() async {
    if (_isPlacingOrder) return;

    while (mounted) {
      final choice = await context.push<PaymentChoice>('/payment-method');
      if (choice == null) return;
      if (!mounted) return;

      final orderId = await _confirmOrder(
        cart: ref.read(cartProvider),
        checkout: ref.read(checkoutProvider),
        paymentChoice: choice,
      );
      if (orderId == null) return;
      if (!mounted) return;

      if (choice == PaymentChoice.cashOnDelivery) {
        _commitPlacedOrder(orderId);
        context.go('/orders/track');
        return;
      }

      final settled = await _runOnlinePayment(orderId: orderId);
      if (!mounted) return;

      if (settled) {
        _commitPlacedOrder(orderId);
        context.go('/orders/track');
        return;
      }

      // Nothing was paid, so the order goes back out entirely — basket rows,
      // voucher claim and all. The cart and the chosen saving were never
      // cleared, so the customer is left exactly where they were and simply
      // gets the payment page again.
      await PayfastCheckout.discardUnpaidOrder(orderId);
      if (!mounted) return;

      // The bar adopted this order while the customer was on PayFast's page,
      // because at that moment it was a real row and nothing about it looked
      // abandoned. The discard is the one party that knows it is gone, so it is
      // the one that has to say so — otherwise the menu screen goes on showing
      // a pizza being cooked against a bill number the database has no row for.
      // Deliberately unconditional: the discard is best-effort, and it can
      // report "nothing to remove" precisely when the order has already gone,
      // which is the same outcome.
      forgetDeletedLiveOrder(ref, orderId);

      _showMessage(
        'Payment was not completed, so nothing has been ordered. '
        'Your cart is still here.',
      );
    }
  }

  /// Accepts an order as real and everything that hangs off the cart.
  ///
  /// Deliberately separate from placement: an order that is placed and then
  /// discarded must not have emptied the cart or burned the voucher, so both
  /// wait until the order is known to have survived.
  void _commitPlacedOrder(String orderId) {
    ref.read(trackedOrderIdProvider.notifier).state = orderId;
    startFollowingNewlyPlacedOrder(ref);
    ref.read(cartProvider.notifier).clearCart();
    ref.read(discountSelectionProvider.notifier).clear();
  }

  Future<String?> _confirmOrder({
    required CartState cart,
    required CheckoutState checkout,
    required PaymentChoice paymentChoice,
  }) async {
    if (_isPlacingOrder) return null;

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return null;

    final branch = _resolveBranchOrAskCustomer(checkout);
    if (branch == null) return null;
    var resolvedCheckout = ref.read(checkoutProvider);

    if (resolvedCheckout.isDelivery && resolvedCheckout.address == null) {
      // Resolved late rather than refused. `_syncCheckout` sets the default as
      // soon as addresses load, but there is a window where checkout can be
      // reached before that lands — and in that window the address card was
      // already RENDERING the default address, so refusing here told a customer
      // to "select a delivery address" while showing them one already selected.
      //
      // The unfiltered list is used deliberately: the address currently applied
      // to the location is a perfectly good delivery address, and hiding it
      // here could leave a customer with exactly one saved place unable to order.
      final addresses =
          ref.read(addressesFutureProvider).value ?? const <UserAddress>[];
      final fallback = defaultSavedAddress(addresses);

      if (fallback == null) {
        _showMessage('Please select a delivery address.');
        return null;
      }

      ref
          .read(checkoutProvider.notifier)
          .selectAddress(fallback, branches: _loadedBranches);
      resolvedCheckout = ref.read(checkoutProvider);
    }

    // The rider cannot read the customer's profile or address row, so the
    // contact they need to make the delivery is frozen onto the order here.
    //
    // This must be awaited, not `ref.read(...).value`: reading a cold
    // FutureProvider returns AsyncLoading, whose value is null, which silently
    // wrote empty contact details onto every order placed before the profile
    // happened to be cached.
    UserProfile? customerProfile;
    try {
      customerProfile = await ref.read(profileFutureProvider.future);
    } catch (_) {
      customerProfile = null;
    }
    if (customerProfile == null) {
      if (!mounted) return null;
      setState(() => _isPlacingOrder = false);
      _showMessage(
        'We could not load your contact details. Please try again.',
        isError: true,
      );
      return null;
    }

    // The fee belongs to the branch that will fulfil the order, so it is read
    // here rather than assumed. A branch with no fee configured blocks the
    // order instead of silently charging nothing.
    final deliveryFee = await ref.read(
      branchDeliveryFeeProvider(branch.id).future,
    );
    if (deliveryFee == null) {
      if (!mounted) return null;
      setState(() => _isPlacingOrder = false);
      _showMessage(
        'This branch has not set a delivery fee yet. Please choose another '
        'branch or try again shortly.',
        isError: true,
      );
      return null;
    }

    setState(() => _isPlacingOrder = true);
    final totals = OrderTotals(
      subtotal: cart.subtotal,
      orderType: resolvedCheckout.orderType,
      branchDeliveryFee: deliveryFee,
    );
    final deliveryAddress =
        resolvedCheckout.isDelivery ? resolvedCheckout.address : null;
    late final String placedOrderId;
    try {
      final order = Order(
        customerId: userId,
        branchId: branch.id,
        addressId: deliveryAddress?.id,
        orderType: resolvedCheckout.orderType,
        totals: totals,
        paymentMethod: paymentChoice == PaymentChoice.cashOnDelivery
            ? 'cod'
            : 'online',
        items: cart.items
            .map(
              (ci) => OrderItem(
                menuItemId: ci.item.id,
                quantity: ci.quantity,
                unitPrice: ci.unitPrice,
              ),
            )
            .toList(),
        customerName: customerProfile.fullName.trim(),
        customerPhone: customerProfile.phone.trim(),
        deliveryAddress: deliveryAddress?.addressLine.trim() ?? '',
        deliveryLatitude: deliveryAddress?.latitude,
        deliveryLongitude: deliveryAddress?.longitude,
      );
      placedOrderId =
          await ref.read(ordersRepositoryProvider).placeOrder(order);
    } catch (e) {
      if (!mounted) return null;
      setState(() => _isPlacingOrder = false);
      _showMessage(_orderErrorText(e), isError: true);
      return null;
    }

    // The saving is claimed against the order that now exists, so it is computed
    // by the database from the rows that were actually inserted.
    //
    // Exactly one saving ever goes on an order, and the customer chose at most
    // one, so the branch below is "voucher else points else welcome offer" and
    // nothing else can be attempted. The database enforces the same rule again
    // from its side — each of the three functions refuses an order that already
    // carries another — so a modified client cannot stack two by calling all
    // three.
    final selection = _selection;
    var voucherWarning = '';
    LoyaltyRedemption? pointsRedemption;
    FirstOrderOffer? firstOrderRedemption;

    // What the cart told the customer the welcome offer was worth, so a refusal
    // can be recognised as one. Read from the same family key the cart summary
    // watched, so it is already resolved rather than a second round trip.
    final expectedFirstOrderSaving = selection.hasCustomerChosenSaving
        ? 0
        : (ref
                .read(firstOrderOfferProvider((
                  subtotal: cart.subtotal,
                  branchId: branch.id,
                )))
                .valueOrNull
                ?.discountAmount ??
            0);

    if (selection.hasVoucher) {
      try {
        // A code that passed the check at apply time can still be refused here —
        // it may have expired, or the customer may have reached their limit on
        // another device — so the database's redemption verdict is the one that
        // counts, and a refusal is reported rather than quietly ignored.
        final redemption =
            await ref.read(voucherRepositoryProvider).redeemVoucher(
                  code: selection.voucher!.code,
                  orderId: placedOrderId,
                );
        if (!redemption.isUsable) {
          voucherWarning = redemption.message;
        }
      } catch (_) {
        voucherWarning = 'Your voucher could not be applied to this order.';
      }
    } else if (selection.hasPoints) {
      try {
        // The verdict is kept either way: a refusal carries the database's own
        // wording — "You have N points available", "Points can only be spent
        // before an order is delivered" — which is more useful than anything
        // generic said in its place, and the order still stands.
        pointsRedemption =
            await ref.read(loyaltyRepositoryProvider).redeemPoints(
                  orderId: placedOrderId,
                  points: selection.pointsToSpend,
                );
      } catch (_) {
        pointsRedemption = null;
      }

      // Points moved, so the cached balance is now wrong. Re-read rather than
      // subtracting locally: the ledger is the only thing that knows the true
      // figure, and a clamped spend makes arithmetic guesswork.
      refreshLoyaltyBalance(ref);
    } else {
      // No voucher and no points, so the automatic welcome offer applies if this
      // really is the customer's first order. There is nothing for the customer
      // to accept and nothing is sent about it — being signed in is the whole
      // trigger. `apply_first_order_discount` re-checks "has this customer
      // ordered before?" and the fulfilling branch's settings against the rows
      // that were actually inserted, so a client that asks twice, or for an
      // order that is not their first, is refused rather than believed.
      try {
        firstOrderRedemption = await ref
            .read(voucherRepositoryProvider)
            .applyFirstOrderDiscount(orderId: placedOrderId);
      } catch (_) {
        // The order still stands at full price and there is nothing useful to
        // say: nothing was promised in the flow, and the cart summary already
        // told the customer whether the offer applied.
        firstOrderRedemption = null;
      }
    }

    // The cart, the saving and the tracking pin are all committed by
    // `_commitPlacedOrder`, not here. This order may still be rolled back if the
    // customer backs out of PayFast's page, and an order that gets discarded
    // must not have taken the cart or the voucher with it.
    if (!mounted) return null;
    if (voucherWarning.isNotEmpty) {
      _showMessage(voucherWarning, isError: true);
    } else if (pointsRedemption != null) {
      // The database's own numbers, not a figure worked out here. If it clamped
      // the request, `message` says what was actually spent.
      _showMessage(
        pointsRedemption.message,
        isError: !pointsRedemption.ok,
      );
    } else if (expectedFirstOrderSaving > 0 &&
        (firstOrderRedemption?.discountAmount ?? 0) <= 0) {
      // The cart promised a welcome offer and the database did not grant one.
      // Saying nothing would leave the customer watching a tracking screen
      // showing a total higher than the one they confirmed, with no idea why —
      // so the gap is named even though the order itself is fine.
      _showMessage(
        firstOrderRedemption?.message.isNotEmpty ?? false
            ? firstOrderRedemption!.message
            : 'The welcome offer could not be applied to this order.',
        isError: true,
      );
    }

    // The spinner belongs to placing the order, which is done. Leaving it up
    // would strand the button behind a spinner the customer cannot dismiss.
    if (!mounted) return null;
    setState(() => _isPlacingOrder = false);

    return placedOrderId;
  }

  /// Opens PayFast's page, then waits for the order to actually be marked paid.
  ///
  /// Returns whether the order should be KEPT. False means the customer walked
  /// away without paying and the caller should take the order back out.
  ///
  /// Nothing here decides the outcome. The WebView closing tells us only that
  /// the customer reached the redirect URL, which is not proof of anything — the
  /// browser can be closed mid-checkout and the URL can be typed by hand. The
  /// order flips to 'paid' only when `payfast-ipn` receives PayFast's IPN and
  /// `apply_payment_result` accepts it, so this waits for that and nothing more.
  Future<bool> _runOnlinePayment({required String orderId}) async {
    final email = ref.read(authStateProvider).user?.email ?? '';
    final phone = ref.read(profileFutureProvider).value?.phone.trim() ?? '';

    // Covers the token call only. The WebView brings its own screen, and putting
    // a blocking barrier over it would stop the customer cancelling — which is
    // the exact thing this flow has to handle.
    _showProcessingOverlay();

    final outcome = await PayfastCheckout.pay(
      context,
      orderId: orderId,
      customerEmail: email,
      customerMobile: phone,
      description: 'MrPizza food order',
      onError: (message) => _showMessage(message, isError: true),
    );

    if (!mounted) return true;
    _dismissProcessingOverlay();

    // Closed without paying, or sent to the failure page. Either way nothing is
    // owed and the order should not survive. The database refuses the rollback
    // if a payment did land in the meantime, so this cannot destroy a paid
    // order even if PayFast's IPN beat us to it.
    if (outcome == PayfastOutcome.cancelled ||
        outcome == PayfastOutcome.reachedFailure) {
      return false;
    }

    // The token call itself failed, so there may be no basket row at all.
    if (outcome == null) return false;

    _showProcessingOverlay(message: 'Confirming your payment...');
    final confirmed = await PayfastCheckout.waitForPaid(orderId);
    if (!mounted) return true;
    _dismissProcessingOverlay();

    // Timed out. The IPN may still be in flight, so the order is KEPT rather
    // than rolled back — deleting an order that turns out to have been paid is
    // far worse than leaving one that was not. Saying so beats spinning forever
    // or claiming it failed.
    if (!confirmed) {
      _showMessage(
        'We are still confirming your payment. If it goes through it will '
        'appear on this order shortly.',
        isError: true,
      );
    }

    return true;
  }

  /// A blocking spinner over the checkout screen.
  ///
  /// Dismissible is off on purpose: without one of these the button looks dead
  /// while the token call and the IPN wait are both in flight, and a customer
  /// who taps again places a second order.
  void _showProcessingOverlay({String message = 'Opening payment page...'}) {
    if (!mounted || _processingOverlayOpen) return;
    _processingOverlayOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(height: 18),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _dismissProcessingOverlay() {
    if (!mounted || !_processingOverlayOpen) return;
    _processingOverlayOpen = false;
    Navigator.of(context, rootNavigator: true).pop();
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
      body: cart.items.isEmpty
          ? _buildEmptyState()
          : _buildCheckout(cart, checkout, addressesAsync, branchesAsync),
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
    // Fee shown before the order is placed. Falls back to 0 only while the read
    // is in flight, so the summary renders; placement re-reads it and refuses
    // to proceed if the branch genuinely has no fee.
    final branchId = checkout.branch?.id;
    final feeAsync = branchId == null
        ? const AsyncValue<double?>.data(null)
        : ref.watch(branchDeliveryFeeProvider(branchId));

    final totals = OrderTotals(
      subtotal: cart.subtotal,
      orderType: checkout.orderType,
      branchDeliveryFee: feeAsync.valueOrNull ?? 0,
    );

    // The welcome offer depends on what the items come to and which branch is
    // fulfilling, so it is re-asked whenever either changes rather than read
    // once when the screen opened.
    final offerAsync = ref.watch(firstOrderOfferProvider((
      subtotal: cart.subtotal,
      branchId: branchId,
    )));
    final selection = ref.watch(discountSelectionProvider);
    final discount = resolvedDiscountSummary(
      selection: selection,
      firstOrderOffer: offerAsync.valueOrNull,
      loyalty: ref.watch(discountLoyaltyBalanceProvider),
    );

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
          _buildDiscountSection(selection, discount),
          const SizedBox(height: 20),
          _buildSummarySection(totals, discount),
          const SizedBox(height: 30),
          _buildConfirmButton(checkout, totals, discount),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// The one place a saving can be chosen from the cart: a button through to
  /// `/apply-discount`.
  ///
  /// The controls themselves moved off this screen so the totals sit above the
  /// fold on a small phone instead of below a code field and a points stepper.
  /// What is applied is still stated here — a single line with the saving and a
  /// way to remove it — because a customer looking at the total needs to see why
  /// it is lower than the subtotal without navigating anywhere.
  Widget _buildDiscountSection(
    DiscountSelection selection,
    AppliedDiscountSummary? discount,
  ) {
    final hasApplied = selection.hasCustomerChosenSaving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MrSectionTitle(title: 'Voucher & Loyalty Points'),
        const SizedBox(height: 6),
        const MrFadeDivider(),
        const SizedBox(height: 14),
        InkWell(
          onTap: () => context.push('/apply-discount'),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: hasApplied ? AppColors.success : AppColors.border,
                width: hasApplied ? 1.5 : 1,
              ),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadowSoft,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  hasApplied
                      ? Icons.check_circle_rounded
                      : Icons.local_offer_outlined,
                  color: hasApplied ? AppColors.success : AppColors.primary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasApplied
                            ? discount!.label
                            : 'Apply voucher or loyalty points',
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: hasApplied
                              ? AppColors.success
                              : AppColors.textPrimary,
                        ),
                      ),
                      if (hasApplied) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Saving Rs. ${discount!.saving.toInt()}'
                          '${discount.isFirstOrderOffer ? ' · applied automatically' : ''}'
                          ' · tap to change',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (hasApplied)
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close_rounded,
                        color: AppColors.textLight, size: 20),
                    onPressed: () {
                      ref.read(discountSelectionProvider.notifier).clear();
                      _showMessage('Removed');
                    },
                  )
                else
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textLight, size: 22),
              ],
            ),
          ),
        ),
      ],
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
      return [
        _sectionTitle('Delivery Details'),
        const SizedBox(height: 12),
        _loadingBox()
      ];
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

  Widget _deliveryAddressCard(
      List<UserAddress> addresses, CheckoutState checkout) {
    final address = checkout.address ??
        addresses.firstWhere((a) => a.isDefault, orElse: () => addresses.first);
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

  /// Where the customer will collect the order.
  ///
  /// Shows the branch the app worked out, not a list. The full picker was the
  /// thing that made pickup look harder than it is: the branch had already been
  /// resolved from the customer's pin before this screen was ever drawn, and
  /// then a list of every branch was put on top of it asking them to make a
  /// decision they had not needed to make. Delivery has never done this — it
  /// shows the resolved address and offers a picker on tap — and pickup now
  /// behaves the same way.
  ///
  /// The full list is still one tap away, because the automatic pick can be
  /// wrong: a customer in Mandian may want to collect from the Mansehra branch
  /// on a day they are passing through.
  List<Widget> _buildPickupSection(
    AsyncValue<BranchCatalog> branchesAsync,
    CheckoutState checkout,
  ) {
    return [
      _sectionTitle('Pickup Details'),
      const SizedBox(height: 12),
      branchesAsync.when(
        loading: () => _loadingBox(),
        error: (error, _) =>
            _errorBox(() => ref.invalidate(branchesFutureProvider)),
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

          final branch = checkout.branch;
          if (branch == null) {
            // Nothing to show and nothing to correct. Never a dead end: the
            // same card Confirm Order uses when a delivery branch could not be
            // resolved, opening the same picker.
            return _unresolvedBranchCard();
          }

          return _pickupBranchCard(branch, checkout.branchWasChosenManually);
        },
      ),
    ];
  }

  /// The resolved collection branch, tappable to change it.
  ///
  /// Says "nearest" only when the branch was actually proven closest. For
  /// pickup the proof is the customer's own map pin, and that is only as good
  /// as the pin — so the wording distinguishes a proven pick from a defaulted
  /// one rather than claiming "nearest" for whichever branch sorted first.
  Widget _pickupBranchCard(Branch branch, bool wasChosenManually) {
    final label = wasChosenManually
        ? 'Collecting from ${branch.name}'
        : 'Collecting from ${branch.name} (nearest branch)';

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _showBranchPickerSheet(_loadedBranches),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
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
              icon: Icons.storefront_rounded,
              color: AppColors.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Tap to collect from a different branch',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textLight),
          ],
        ),
      ),
    );
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
    OrderTotals totals,
    AppliedDiscountSummary? discount,
  ) {
    final finalTotal =
        (totals.total - (discount?.saving ?? 0)).clamp(0.0, double.infinity);

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
                _deliveryChargeLabel(totals),
                color: _selection.voucher?.isFreeDelivery == true
                    ? AppColors.success
                    : null,
              ),
              if (discount != null) ...[
                const SizedBox(height: 8),
                _summaryRow(
                  'Discount (${discount.label})',
                  '-Rs. ${discount.saving.toInt()}',
                  color: AppColors.success,
                ),
              ],
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
                    'Rs. ${finalTotal.toInt()}',
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

  /// The delivery charge line, shown as waived when a `free_delivery` voucher
  /// is in force so the customer can see the fee they are not paying.
  String _deliveryChargeLabel(OrderTotals totals) {
    if (_selection.voucher?.isFreeDelivery == true) {
      return 'Free (Rs. ${totals.deliveryFee.toInt()} waived)';
    }
    return 'Rs. ${totals.deliveryFee.toInt()}';
  }

  Widget _summaryRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: color ?? AppColors.textSecondary,
                fontWeight:
                    color != null ? FontWeight.w700 : FontWeight.normal)),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color ?? AppColors.textPrimary)),
      ],
    );
  }

  Widget _buildConfirmButton(
    CheckoutState checkout,
    OrderTotals totals,
    AppliedDiscountSummary? discount,
  ) {
    // Button is enabled when:
    // - Delivery: an address is selected (branch auto-resolves from address)
    // - Pickup: a branch is selected
    // - Not already submitting
    final hasAddress = checkout.address != null;
    final hasBranch = checkout.branch != null;
    final canPlace = !_isPlacingOrder &&
        (checkout.isDelivery ? hasAddress || hasBranch : hasBranch);
    final finalTotal =
        (totals.total - (discount?.saving ?? 0)).clamp(0.0, double.infinity);

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton(
        onPressed: canPlace
            ? () => _choosePaymentMethod()
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
                    'Continue with Payment',
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
                    'Rs. ${finalTotal.toInt()}',
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
