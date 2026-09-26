import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/location/data/geolocator_device_location_source.dart';
import '../../features/location/data/location_repository.dart';
import '../../features/location/data/nominatim_address_lookup.dart';
import '../../features/profile/models/profile.dart';

/// Where the app lives, for the OpenStreetMap User-Agent.
///
/// OpenStreetMap's usage policy requires a way to contact the operator of an
/// app that uses Nominatim. Replace the email below with a real monitored
/// address before shipping to the public — see docs/superpowers/specs.
const String nominatimUserAgent = 'MrPizza/1.0 (contact@example.com)';

/// The single location repository used by the app: real device GPS plus
/// OpenStreetMap reverse geocoding.
final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  final lookup = NominatimAddressTextLookup(userAgent: nominatimUserAgent);
  ref.onDispose(lookup.dispose);

  return LocationRepository(
    deviceSource: GeolocatorDeviceLocationSource(),
    addressLookup: lookup,
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
}

/// Owns the customer's current location for the app session.
class LocationNotifier extends StateNotifier<LocationState> {
  final LocationRepository repository;

  LocationNotifier({required this.repository})
      : super(const LocationState());

  /// The state a fresh notifier starts in, with no address and no pin.
  LocationState build() => const LocationState();

  /// Records an address the customer typed or picked by hand.
  ///
  /// Any earlier pin is dropped: coordinates from a previous capture describe
  /// somewhere else, and keeping them would make the app match the branch to
  /// the wrong place.
  void setLocation(String newAddress) {
    state = LocationState(address: newAddress, isSet: true);
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
    } on LocationCaptureException catch (error) {
      state = LocationState(
        errorMessage: error.message,
        settingsMustBeOpened: error.settingsMustBeOpened,
      );
    }
  }

  /// Sends the customer to the OS settings page to grant location access.
  Future<void> openAppSettings() => repository.openAppSettings();
}

final locationProvider =
    StateNotifierProvider<LocationNotifier, LocationState>((ref) {
  return LocationNotifier(repository: ref.watch(locationRepositoryProvider));
});
