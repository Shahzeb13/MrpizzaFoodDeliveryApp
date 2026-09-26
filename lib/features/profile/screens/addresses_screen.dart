import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/location_provider.dart';
import '../../../core/theme/app_colors.dart';
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
      backgroundColor: AppColors.surface,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const MrIconWell(
                            icon: Icons.add_location_alt_rounded,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Add New Address',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _labelController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Label (optional)',
                          hintText: 'Leave blank and we will name it for you',
                          prefixIcon: Icon(Icons.label_outline_rounded),
                        ),
                        // Deliberately never validated. The label is a nicety for
                        // the customer's own list; making it required meant the
                        // form could not be completed without inventing one, which
                        // is the friction this screen is meant to avoid.
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _addressController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Complete Address Details',
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Address is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildUseLocationButton(setSheetState),
                      if (_locationError != null)
                        _buildLocationError(setSheetState),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saving
                              ? null
                              : () => _submitNewAddress(setSheetState),
                          child: Text(_saving ? 'Saving...' : 'Save Address'),
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
        height: 48,
        child: Center(
          child: SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    final hasPin = _capturedLatitude != null && _capturedLongitude != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _useCurrentLocation(setSheetState),
            icon: Icon(
              hasPin ? Icons.check_circle_rounded : Icons.my_location_rounded,
              size: 18,
            ),
            label: Text(hasPin
                ? 'Location Added — Tap to Update'
                : 'Use My Current Location'),
          ),
        ),
        if (hasPin) ...[
          const SizedBox(height: 6),
          Text(
            'Pinned at ${_capturedLatitude!.toStringAsFixed(5)}, '
            '${_capturedLongitude!.toStringAsFixed(5)}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ],
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
  }

  @override
  Widget build(BuildContext context) {
    final addressesAsync = ref.watch(addressesFutureProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Addresses'),
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: addressesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const MrIconWell(
                icon: Icons.error_outline,
                color: AppColors.textSecondary,
                background: AppColors.sand,
                size: 28,
              ),
              const SizedBox(height: 12),
              Text(
                'Could not load your addresses',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => ref.invalidate(addressesFutureProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (addresses) {
          if (addresses.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MrIconWell(
                    icon: Icons.location_off_rounded,
                    color: AppColors.textSecondary,
                    background: AppColors.sand,
                    size: 28,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'No saved addresses yet',
                    style: TextStyle(
                        fontSize: 16, color: AppColors.textSecondary),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Add your first delivery address below',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textLight),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: addresses.length,
            itemBuilder: (context, index) {
              final address = addresses[index];
              return MrCard(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: AppColors.primaryTint,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _iconForLabel(address.label),
                            color: AppColors.primary,
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                  ),
                                  if (address.isDefault) ...[
                                    const SizedBox(width: 8),
                                    const MrEyebrow(
                                      text: 'Default',
                                      background: AppColors.primaryTint,
                                      foreground: AppColors.primaryDark,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                address.addressLine,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(height: 1.35),
                              ),
                              if (address.latitude != null &&
                                  address.longitude != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Lat: ${address.latitude!.toStringAsFixed(6)}  '
                                  'Lng: ${address.longitude!.toStringAsFixed(6)}',
                                  style:
                                      Theme.of(context).textTheme.labelMedium,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!address.isDefault)
                          TextButton.icon(
                            onPressed: () => _setDefault(address),
                            icon: const Icon(Icons.star_outline, size: 18),
                            label: const Text('Set as Default'),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AppColors.warning, size: 20),
                          onPressed: () => _confirmDelete(address),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _showAddAddressDialog,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Add New Address'),
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