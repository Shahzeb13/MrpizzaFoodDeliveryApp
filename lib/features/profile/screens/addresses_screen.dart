import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';
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
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  void _showAddAddressDialog() {
    _labelController.clear();
    _addressController.clear();
    _latitudeController.clear();
    _longitudeController.clear();

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
                          labelText: 'Label (e.g. Home, Hostel)',
                          prefixIcon: Icon(Icons.label_outline_rounded),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Label is required';
                          }
                          return null;
                        },
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
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _latitudeController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true, signed: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^-?\d*\.?\d*')),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Latitude (optional)',
                                prefixIcon: Icon(Icons.explore_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _longitudeController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true, signed: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^-?\d*\.?\d*')),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Longitude (optional)',
                                prefixIcon: Icon(Icons.explore_outlined),
                              ),
                            ),
                          ),
                        ],
                      ),
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

  Future<void> _submitNewAddress(StateSetter setSheetState) async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    setSheetState(() => _saving = true);

    try {
      await ref.read(profileRepositoryProvider).addAddress(
            userId: userId,
            label: _labelController.text.trim(),
            addressLine: _addressController.text.trim(),
            latitude: double.tryParse(_latitudeController.text.trim()),
            longitude: double.tryParse(_longitudeController.text.trim()),
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