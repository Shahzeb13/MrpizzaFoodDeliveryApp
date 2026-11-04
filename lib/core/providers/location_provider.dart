import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/location/data/geocoding_service.dart';
import '../../features/location/data/geolocator_device_location_source.dart';
import '../../features/location/data/location_repository.dart';
import '../../features/profile/models/profile.dart';
import '../storage/local_storage.dart';

/// The app's one geocoder: reverse for the delivery map's pin, forward for a
/// typed address.
///
/// Mapbox Geocoding v6 serves both directions, and it runs on the same public
/// token the map already uses, so there is no second service, no second key and
/// no second failure mode to reason about. It replaced OpenStreetMap's
/// Nominatim, which needed a monitored contact address in its User-Agent and
/// answered `403` when that contact was a placeholder.
final geocodingServiceProvider = Provider<GeocodingService>((ref) {
  final service = GeocodingService();
  ref.onDispose(service.dispose);

  return service;
});

/// The single location repository used by the app: real device GPS plus
/// Mapbox reverse geocoding.
final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  final geocoder = ref.watch(geocodingServiceProvider);

  return LocationRepository(
    deviceSource: GeolocatorDeviceLocationSource(),
    addressLookup: geocoder,
    coordinateLookup: geocoder,
  );
});

/// What the app currently knows about the customer's position.
class LocationState {
  /// The street address to show and save. May be empty even when a GPS pin
  /// exists, because reverse geocoding is allowed to fail.
  final String address;

  /// True once the customer has either captured their position or typed an
  /// address.
  final bool isSet;

  /// The GPS pin, or null when there is none — either nothing was captured yet
  /// or the customer typed their address by hand.
  final double? latitude;
  final double? longitude;

  /// True while a "use my location" request is in flight.
  final bool isCapturing;

  /// Why the last capture failed, phrased for the customer. Null when the last
  /// attempt succeeded or none has been made.
  final String? errorMessage;

  /// True when the failure can only be fixed in the OS settings page, so the
  /// UI should offer an "Open settings" button.
  final bool settingsMustBeOpened;

  const LocationState({
    this.address = '',
    this.isSet = false,
    this.latitude,
    this.longitude,
    this.isCapturing = false,
    this.errorMessage,
    this.settingsMustBeOpened = false,
  });

  /// True when a GPS pin is available, which is what nearest-branch matching
  /// needs before it can honestly call a branch the closest one.
  bool get hasCoordinates => latitude != null && longitude != null;

  LocationState copyWith({
    String? address,
    bool? isSet,
    double? latitude,
    double? longitude,
    bool? isCapturing,
    String? errorMessage,
    bool? settingsMustBeOpened,
  }) {
    return LocationState(
      address: address ?? this.address,
      isSet: isSet ?? this.isSet,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isCapturing: isCapturing ?? this.isCapturing,
      errorMessage: errorMessage ?? this.errorMessage,
      settingsMustBeOpened: settingsMustBeOpened ?? this.settingsMustBeOpened,
    );
  }
}

/// Owns the customer's current location for the app session, and remembers it
/// across app restarts.
///
/// The delivery address a guest typed, or the pin they put down on the map, is
/// saved through [LocalStore] so reopening the app lands them back where their
/// checkout was. Only settled, useful positions are stored — a capture that is
/// still running, or one that failed, writes nothing and erases nothing, so a
/// GPS miss can never delete the address the customer already had.
class LocationNotifier extends StateNotifier<LocationState> {
  final LocationRepository repository;

  LocationNotifier({required this.repository}) : super(const LocationState()) {
    // Restoring waits for the first read and fills the (still empty) state
    // within milliseconds; a store that never opens leaves the session
    // starting fresh, exactly as it did before persistence existed.
    _storeReady = LocalStore.instance.ready();
    unawaited(_hydrate());
  }

  late final Future<SharedPreferences?> _storeReady;
  bool _changedSinceBoot = false;

  /// The state a fresh notifier starts in, with no address and no pin.
  LocationState build() => const LocationState();

  Future<void> _hydrate() async {
    final prefs = await _storeReady;
    if (prefs == null) return;

    final restored = _decodeStoredLocation(
      LocalStore.instance.readString(localStorageLocationKey),
    );

    // A position captured in the milliseconds before storage answered has
    // already superseded the stored one.
    if (!mounted || _changedSinceBoot || restored == null) return;

    state = restored;
  }

  /// Decodes what [_recordChange] wrote, or null when nothing usable is
  /// stored. A typed address may carry no coordinates; a bare coordinate pair
  /// without an address is half a pick and is dropped.
  static LocationState? _decodeStoredLocation(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;

      final address = decoded['address']?.toString() ?? '';
      final rawLatitude = decoded['latitude'];
      final rawLongitude = decoded['longitude'];
      final latitude = rawLatitude is num ? rawLatitude.toDouble() : null;
      final longitude = rawLongitude is num ? rawLongitude.toDouble() : null;

      if (address.trim().isEmpty && (latitude == null || longitude == null)) {
        return null;
      }

      return LocationState(
        address: address,
        isSet: true,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (_) {
      return null;
    }
  }

  /// Saves the current position for the next app run. Nothing is written for
  /// still-running captures, failed captures or a never-set state — those say
  /// nothing about where the customer wants their food, and writing them would
  /// destroy a good stored address.
  ///
  /// [forgetStored] is the explicit clear: the customer dismissed their
  /// address, so the stored one must not come back.
  void _recordChange({bool forgetStored = false}) {
    _changedSinceBoot = true;
    unawaited(() async {
      await _storeReady;
      if (!mounted) return;

      if (forgetStored) {
        await LocalStore.instance.writeString(localStorageLocationKey, null);
        return;
      }

      final settled = state;
      final worthKeeping = settled.isSet &&
          !settled.isCapturing &&
          settled.errorMessage == null &&
          (settled.address.trim().isNotEmpty || settled.hasCoordinates);
      if (!worthKeeping) return;

      await LocalStore.instance.writeString(
        localStorageLocationKey,
        jsonEncode({
          'address': settled.address,
          if (settled.latitude != null) 'latitude': settled.latitude,
          if (settled.longitude != null) 'longitude': settled.longitude,
        }),
      );
    }());
  }

  /// Records an address the customer typed or picked by hand.
  ///
  /// Any earlier pin is dropped: coordinates from a previous capture describe
  /// somewhere else, and keeping them would make the app match the branch to
  /// the wrong place.
  ///
  /// The typed text is stored immediately, then geocoded. Geocoding only runs
  /// to work out the closest branch, so a miss leaves the customer with the
  /// address they typed and no pin rather than an error — [LocationState]
  /// carries no geocoding failure, because nothing actually broke for them.
  Future<void> setLocation(String newAddress) async {
    final trimmed = newAddress.trim();
    state = LocationState(address: trimmed, isSet: true);
    if (trimmed.isEmpty) {
      _recordChange(forgetStored: true);
      return;
    }
    _recordChange();

    state = state.copyWith(isCapturing: true);
    final coordinates = await repository.geocodeAddressText(trimmed);
    if (!state.isSet || state.address != trimmed) return;

    state = state.copyWith(
      latitude: coordinates?.latitude,
      longitude: coordinates?.longitude,
      isCapturing: false,
    );
    _recordChange();
  }

  /// Applies one of the customer's saved addresses, keeping the coordinates
  /// that were stored with it.
  ///
  /// Carrying the pin matters: it is what lets checkout name the genuinely
  /// closest branch instead of guessing.
  void applySavedAddress(UserAddress address) {
    state = LocationState(
      address: address.addressLine,
      isSet: true,
      latitude: address.latitude,
      longitude: address.longitude,
    );
    _recordChange();
  }

  /// Asks the device for a position, then fills in the address text.
  ///
  /// Never throws: a failure is reported through [LocationState.errorMessage]
  /// so the customer can keep typing their address instead.
  Future<void> useCurrentLocation() async {
    state = LocationState(
      address: state.address,
      isSet: state.isSet,
      isCapturing: true,
    );

    try {
      final captured = await repository.captureCurrentLocation();
      state = LocationState(
        address: captured.hasAddressText ? captured.addressLine : '',
        isSet: true,
        latitude: captured.latitude,
        longitude: captured.longitude,
      );
      _recordChange();
    } on LocationCaptureException catch (error) {
      state = LocationState(
        errorMessage: error.message,
        settingsMustBeOpened: error.settingsMustBeOpened,
      );
    }
  }

  /// Applies a position the customer chose by hand on the delivery map.
  ///
  /// The coordinates come from the map camera's centre and the text from the
  /// city/area/landmark they described, so both are kept together. A fresh
  /// [LocationState] is built rather than using [copyWith], because `copyWith`
  /// cannot clear a field — and confirming a new pick must drop the previous
  /// pin and address outright, not merge them.
  void applyMapPick({
    required double latitude,
    required double longitude,
    required String addressText,
  }) {
    state = LocationState(
      address: addressText.trim(),
      isSet: true,
      latitude: latitude,
      longitude: longitude,
    );
    _recordChange();
  }

  /// Sends the customer to the OS settings page to grant location access.
  Future<void> openAppSettings() => repository.openAppSettings();
}

final locationProvider =
    StateNotifierProvider<LocationNotifier, LocationState>((ref) {
  return LocationNotifier(repository: ref.watch(locationRepositoryProvider));
});
