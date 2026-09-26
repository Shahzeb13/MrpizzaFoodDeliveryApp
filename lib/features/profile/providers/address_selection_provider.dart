import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/location_provider.dart';
import '../data/address_book.dart';
import '../data/profile_repository.dart';
import '../models/profile.dart';
import 'profile_provider.dart';

/// Outcome of saving the location the customer just picked.
class SaveLocationResult {
  /// The address now on file, whether it was just inserted or already existed.
  final UserAddress address;

  /// True when a new row was created, false when an existing one was reused.
  final bool wasCreated;

  const SaveLocationResult({required this.address, required this.wasCreated});
}

/// Thrown when a location cannot be saved, phrased for the customer.
class AddressSaveException implements Exception {
  final String message;

  const AddressSaveException(this.message);

  @override
  String toString() => message;
}

/// Persists the customer's chosen location so it shows up in My Addresses and
/// can be attached to an order.
///
/// Selecting a location used to update the in-memory pin only, which is exactly
/// why My Addresses stayed empty and checkout had nothing to select. The inputs
/// are passed in rather than read from a container, so the decision logic can be
/// tested without Supabase.
class AddressSelectionNotifier {
  final ProfileRepository repository;

  const AddressSelectionNotifier(this.repository);

  /// Saves a location, reusing a saved address when the point or the text is
  /// already on file instead of creating a near-duplicate.
  ///
  /// Throws [AddressSaveException] when there is nothing meaningful to save or
  /// the write fails. Returns null when there is no signed-in user, since an
  /// anonymous visitor has nowhere to store an address.
  Future<SaveLocationResult?> saveLocation({
    required String? userId,
    required List<UserAddress> savedAddresses,
    required String addressLine,
    required double? latitude,
    required double? longitude,
  }) async {
    if (userId == null) return null;

    final text = addressLine.trim();
    if (text.isEmpty && latitude == null) {
      throw const AddressSaveException(
        'Pick a location on the map or type an address first.',
      );
    }

    final outcome = AddressBook.classifyLocationSelection(
      saved: savedAddresses,
      addressLine: text,
      latitude: latitude,
      longitude: longitude,
    );

    // Already on file. Reuse it rather than adding a duplicate row, which is
    // what made the address list fill up with near-identical entries.
    if (outcome.existing != null) {
      return SaveLocationResult(
        address: outcome.existing!,
        wasCreated: false,
      );
    }

    try {
      final stored = await repository.addAddress(
        userId: userId,
        label: outcome.label,
        addressLine: text.isEmpty ? 'Pinned location' : text,
        latitude: latitude,
        longitude: longitude,
        isDefault: outcome.shouldBecomeDefault,
      );

      return SaveLocationResult(address: stored, wasCreated: true);
    } catch (error) {
      throw AddressSaveException('Could not save that location: $error');
    }
  }
}

final addressSelectionProvider = Provider<AddressSelectionNotifier>((ref) {
  return AddressSelectionNotifier(ref.watch(profileRepositoryProvider));
});

/// Saves the location currently held by the app, then refreshes the saved
/// address list so My Addresses and checkout both see the result.
///
/// [typedText] replaces the captured address text, for when the customer typed
/// a correction. Returns null when nobody is signed in.
final saveCurrentLocationProvider =
    Provider<Future<SaveLocationResult?> Function({String? typedText})>((ref) {
  return ({String? typedText}) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return null;

    final location = ref.read(locationProvider);

    // Wait for the list rather than treating "not loaded yet" as "empty",
    // otherwise the first save of a session always inserts a duplicate.
    final saved = await ref.read(addressesFutureProvider.future);

    final result = await ref.read(addressSelectionProvider).saveLocation(
          userId: userId,
          savedAddresses: saved,
          addressLine: (typedText?.trim().isNotEmpty ?? false)
              ? typedText!.trim()
              : location.address,
          latitude: location.latitude,
          longitude: location.longitude,
        );

    if (result != null) {
      ref.invalidate(addressesFutureProvider);
    }
    return result;
  };
});
