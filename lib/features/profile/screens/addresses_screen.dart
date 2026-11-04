import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../core/providers/location_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/neumorphic.dart';
import '../../../core/theme/widgets.dart';
import '../data/address_book.dart';
import '../models/profile.dart';
import '../providers/profile_provider.dart';

class AddressesScreen extends ConsumerStatefulWidget {
  const AddressesScreen({super.key});

  @override
  ConsumerState<AddressesScreen> createState() => _AddressesScreenState();
}

class _AddressesScreenState extends ConsumerState<AddressesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  final _addressController = TextEditingController();

  /// The GPS pin for the address being composed, or null when the customer
  /// typed the address by hand. Kept out of the text fields on purpose —
  /// nobody should have to type coordinates.
  double? _capturedLatitude;
  double? _capturedLongitude;

  bool _saving = false;
  bool _capturingLocation = false;
  String? _locationError;
  bool _settingsMustBeOpened = false;

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  /// Fills the address from the device GPS. Failures show a message and leave
  /// the typed address alone, so the customer is never forced to use GPS.
  Future<void> _useCurrentLocation(StateSetter setSheetState) async {
    setSheetState(() {
      _capturingLocation = true;
      _locationError = null;
      _settingsMustBeOpened = false;
    });

    await ref.read(locationProvider.notifier).useCurrentLocation();
    final location = ref.read(locationProvider);
    if (!mounted) return;

    setSheetState(() {
      _capturingLocation = false;
      if (location.errorMessage != null) {
        _locationError = location.errorMessage;
        _settingsMustBeOpened = location.settingsMustBeOpened;
        return;
      }
      _capturedLatitude = location.latitude;
      _capturedLongitude = location.longitude;
      if (location.address.isNotEmpty) {
        _addressController.text = location.address;
      }
    });
  }

  Future<void> _openLocationSettings(StateSetter setSheetState) async {
    await ref.read(locationProvider.notifier).openAppSettings();
    if (!mounted) return;
    setSheetState(() => _settingsMustBeOpened = false);
  }

  void _showAddAddressDialog() {
    _labelController.clear();
    _addressController.clear();
    _capturedLatitude = null;
    _capturedLongitude = null;
    _locationError = null;
    _settingsMustBeOpened = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF0F3F8),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    offset: Offset(0, -6),
                    blurRadius: 24,
                  ),
                ],
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 14,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Drag Handle Indicator
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD0D7E2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Header Row: Red Location Pin Badge, Title, and Close Button
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE51926),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x55E51926),
                                  offset: Offset(0, 4),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Text(
                              'Add new address',
                              style: TextStyle(
                                fontFamily: 'PlusJakartaSans',
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF141923),
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          // Close Button
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFF0F3F8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white,
                                    offset: Offset(-2, -2),
                                    blurRadius: 5,
                                  ),
                                  BoxShadow(
                                    color: Color(0x2AA6B4C9),
                                    offset: Offset(2, 2),
                                    blurRadius: 5,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Color(0xFF141923),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      // Label (optional) Header
                      const Text(
                        'Label (optional)',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF141923),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Debossed Label Input Field
                      Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5EBF3),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              offset: const Offset(2, 2),
                              blurRadius: 4,
                            ),
                            const BoxShadow(
                              color: Colors.white,
                              offset: Offset(-2, -2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.local_offer_outlined,
                              color: Color(0xFF141923),
                              size: 19,
                            ),
                            const SizedBox(width: 12),
                            Expanded(                              child: TextFormField(
                                controller: _labelController,
                                textCapitalization: TextCapitalization.words,
                                style: const TextStyle(
                                  fontFamily: 'PlusJakartaSans',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF141923),
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Label (optional)',
                                  hintText: 'Home, Office...',
                                  hintStyle: TextStyle(
                                    fontFamily: 'PlusJakartaSans',
                                    color: Color(0xFF758295),
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Complete address details Header
                      const Text(
                        'Complete address details',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF141923),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Debossed Address Input Field
                      Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5EBF3),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              offset: const Offset(2, 2),
                              blurRadius: 4,
                            ),
                            const BoxShadow(
                              color: Colors.white,
                              offset: Offset(-2, -2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              color: Color(0xFF141923),
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _addressController,
                                style: const TextStyle(
                                  fontFamily: 'PlusJakartaSans',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF141923),
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Complete Address Details',
                                  hintText: 'Street, area, landmark',
                                  hintStyle: TextStyle(
                                    fontFamily: 'PlusJakartaSans',
                                    color: Color(0xFF758295),
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Address is required';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Use my current location Button
                      _buildUseLocationButton(setSheetState),
                      if (_locationError != null)
                        _buildLocationError(setSheetState),
                      const SizedBox(height: 22),

                      // Primary Save Address Button
                      GestureDetector(
                        onTap: _saving ? null : () => _submitNewAddress(setSheetState),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE51926),
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x4DE51926),
                                offset: Offset(0, 6),
                                blurRadius: 14,
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _saving ? 'Saving...' : 'Save Address',
                            style: const TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildUseLocationButton(StateSetter setSheetState) {
    if (_capturingLocation) {
      return const SizedBox(
        height: 52,
        child: Center(
          child: SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE51926)),
            ),
          ),
        ),
      );
    }

    final hasPin = _capturedLatitude != null && _capturedLongitude != null;

    return GestureDetector(
      onTap: () => _useCurrentLocation(setSheetState),
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F3F8),
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [
            BoxShadow(
              color: Colors.white,
              offset: Offset(-3, -3),
              blurRadius: 8,
            ),
            BoxShadow(
              color: Color(0x28A6B4C9),
              offset: Offset(3, 3),
              blurRadius: 8,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.gps_fixed_rounded,
              color: Color(0xFFE51926),
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              hasPin
                  ? 'Location added · Tap to update'
                  : 'Use My Current Location',
              style: const TextStyle(
                fontFamily: 'PlusJakartaSans',
                color: Color(0xFFE51926),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationError(StateSetter setSheetState) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _locationError!,
            style: const TextStyle(color: AppColors.warning, fontSize: 13),
          ),
          if (_settingsMustBeOpened) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _openLocationSettings(setSheetState),
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Open Settings'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submitNewAddress(StateSetter setSheetState) async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    setSheetState(() => _saving = true);

    try {
      // A blank label is filled in from the address text, so the customer only
      // types one when they want a specific name.
      final typed = _labelController.text.trim();
      final line = _addressController.text.trim();
      await ref.read(profileRepositoryProvider).addAddress(
            userId: userId,
            label: typed.isNotEmpty
                ? typed
                : AddressBook.deriveLabel(
                    line.isNotEmpty ? line : 'Pinned location',
                  ),
            addressLine: line,
            latitude: _capturedLatitude,
            longitude: _capturedLongitude,
          );
      ref.invalidate(addressesFutureProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Address added successfully!'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to add address. Please try again.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    }
  }

  Future<void> _setDefault(UserAddress address) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null || address.isDefault) return;

    try {
      await ref.read(profileRepositoryProvider).setDefaultAddress(
            userId: userId,
            addressId: address.id,
          );
      ref.invalidate(addressesFutureProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Default address updated'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update default address.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(UserAddress address) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Address'),
          content: Text(
              'Are you sure you want to delete "${address.label}"? This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(profileRepositoryProvider).deleteAddress(address.id);
      ref.invalidate(addressesFutureProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Address deleted'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete address.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    }
  }  @override
  Widget build(BuildContext context) {
    final addressesAsync = ref.watch(addressesFutureProvider);

    return Scaffold(
      backgroundColor: NeuColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'My Addresses',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: NeuColors.textPrimary,
            letterSpacing: -0.4,
          ),
        ),
        leading: Center(
          child: NeuCircleButton(
            size: 40,
            onPressed: () => Navigator.of(context).canPop()
                ? Navigator.of(context).pop()
                : context.go('/home'),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: NeuColors.textPrimary,
            ),
          ),
        ),
      ),
      body: addressesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: NeuColors.primary),
        ),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: NeuColors.textSecondary, size: 36),
              const SizedBox(height: 12),
              const Text(
                'Could not load your addresses',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: NeuColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => ref.invalidate(addressesFutureProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (addresses) {
          if (addresses.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  NeuInset(
                    borderRadius: 30,
                    padding: const EdgeInsets.all(20),
                    child: const Icon(
                      Icons.location_off_rounded,
                      color: NeuColors.textSecondary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No saved addresses yet',
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: NeuColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Add your first delivery address below',
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: NeuColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: addresses.length,
            itemBuilder: (context, index) {
              final address = addresses[index];
              final isDefault = address.isDefault;

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: NeuCard(
                  padding: const EdgeInsets.all(18),
                  borderRadius: 26,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isDefault)
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: NeuColors.primary,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x66E51926),
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            )
                          else
                            NeuInset(
                              borderRadius: 16,
                              padding: const EdgeInsets.all(11),
                              child: const Icon(
                                Icons.location_on_outlined,
                                color: NeuColors.textPrimary,
                                size: 22,
                              ),
                            ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        address.label,
                                        style: const TextStyle(
                                          fontFamily: 'PlusJakartaSans',
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          color: NeuColors.textPrimary,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ),
                                    if (isDefault) ...[
                                      const SizedBox(width: 8),
                                      NeuPillBadge(
                                        label: 'DEFAULT',
                                        textColor: NeuColors.primary,
                                        isInset: true,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  address.addressLine,
                                  style: const TextStyle(
                                    fontFamily: 'PlusJakartaSans',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: NeuColors.textSecondary,
                                    height: 1.3,
                                  ),
                                ),
                                if (address.latitude != null &&
                                    address.longitude != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Lat: ${address.latitude!.toStringAsFixed(6)} · Lng: ${address.longitude!.toStringAsFixed(6)}',
                                    style: const TextStyle(
                                      fontFamily: 'PlusJakartaSans',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: NeuColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (!isDefault)
                            NeuCard(
                              borderRadius: 20,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              onTap: () => _setDefault(address),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.star_outline_rounded,
                                      size: 16, color: NeuColors.primary),
                                  SizedBox(width: 6),
                                  Text(
                                    'Set as default',
                                    style: TextStyle(
                                      fontFamily: 'PlusJakartaSans',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: NeuColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            const SizedBox.shrink(),
                          NeuCircleButton(
                            size: 38,
                            onPressed: () => _confirmDelete(address),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: NeuColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: NeuPrimaryButton(
            onPressed: _showAddAddressDialog,
            label: '+ Add new address',
            showArrow: false,
          ),
        ),
      ),
    );
  }

  IconData _iconForLabel(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('home')) {
      return Icons.home_rounded;
    }
    if (lower.contains('work') ||
        lower.contains('office') ||
        lower.contains('shop')) {
      return Icons.work_rounded;
    }
    if (lower.contains('hostel')) {
      return Icons.school_rounded;
    }
    return Icons.location_on_rounded;
  }
}