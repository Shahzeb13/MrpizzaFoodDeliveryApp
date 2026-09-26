import 'dart:async';

import '../models/captured_location.dart';

/// What the app is allowed to do with the device location right now.
enum LocationPermissionOutcome {
  /// Location may be read.
  granted,

  /// The user said no this time, but asking again is allowed.
  denied,

  /// The user said no permanently, so only the OS settings page can change it.
  deniedForever,
}

/// Reads coordinates from the device GPS.
abstract class DeviceLocationSource {
  /// Asks for permission if needed and reports what the app may do.
  Future<LocationPermissionOutcome> ensurePermission();

  /// Sends the user to the OS settings page for this app.
  Future<void> openAppSettings();

  /// Reads one position fix. Only called once permission is [granted].
  Future<CapturedCoordinates> readCurrentCoordinates();
}

/// Turns coordinates into a human-readable street address.
abstract class AddressTextLookup {
  /// Returns the address for [coordinates], or null when nothing was found.
  Future<String?> lookupAddressText(CapturedCoordinates coordinates);
}

/// A location capture that could not be completed, with a message that is safe
/// to show to the user.
class LocationCaptureException implements Exception {
  final String message;

  /// True when the only way forward is the OS settings page, so the UI should
  /// offer a button that opens settings rather than a plain "try again".
  final bool settingsMustBeOpened;

  const LocationCaptureException(this.message, {this.settingsMustBeOpened = false});

  @override
  String toString() => message;
}

/// Captures the device position and an address string for it.
///
/// Failures are reported as [LocationCaptureException] so the UI can show a
/// message and fall back to manual address entry — location is optional and
/// must never block checkout.
class LocationRepository {
  final DeviceLocationSource deviceSource;
  final AddressTextLookup addressLookup;

  const LocationRepository({
    required this.deviceSource,
    required this.addressLookup,
  });

  /// Captures the current position and its street address.
  ///
  /// Throws [LocationCaptureException] when permission is missing or the GPS
  /// cannot produce a usable fix. A failed *address* lookup is not an error:
  /// the returned [CapturedAddress] simply has an empty `addressLine`.
  Future<CapturedAddress> captureCurrentLocation() async {
    final permission = await deviceSource.ensurePermission();
    switch (permission) {
      case LocationPermissionOutcome.denied:
        throw const LocationCaptureException(
          'Location permission was denied. You can type your address instead, '
          'or allow location access to fill it in automatically.',
        );
      case LocationPermissionOutcome.deniedForever:
        throw const LocationCaptureException(
          'Location permission is blocked. Open app settings and allow '
          'location access, or type your address instead.',
          settingsMustBeOpened: true,
        );
      case LocationPermissionOutcome.granted:
        break;
    }

    final CapturedCoordinates coordinates;
    try {
      coordinates = await deviceSource.readCurrentCoordinates();
    } on LocationCaptureException {
      rethrow;
    } catch (error) {
      throw LocationCaptureException(
        'Could not read your location: $error',
      );
    }

    if (!_isPlausibleEarthCoordinate(coordinates)) {
      throw const LocationCaptureException(
        'Your device returned an unusable location. Please try again outdoors, '
        'or type your address instead.',
      );
    }

    return CapturedAddress(
      latitude: coordinates.latitude,
      longitude: coordinates.longitude,
      addressLine: await _lookupAddressTextOrEmpty(coordinates),
    );
  }

  /// Sends the user to the OS settings page for this app.
  Future<void> openAppSettings() => deviceSource.openAppSettings();

  Future<String> _lookupAddressTextOrEmpty(CapturedCoordinates coordinates) async {
    try {
      final text = await addressLookup.lookupAddressText(coordinates);
      return text?.trim() ?? '';
    } catch (_) {
      // The pin is good even without a street address, so keep it and let the
      // user type the address themselves.
      return '';
    }
  }

  /// Rejects coordinates that cannot be a real customer position. `0,0` is in
  /// the Gulf of Guinea and is what a device reports when it has no fix.
  static bool _isPlausibleEarthCoordinate(CapturedCoordinates coordinates) {
    bool inRange(double value, double min, double max) =>
        value >= min && value <= max && !value.isNaN;

    return inRange(coordinates.latitude, -90, 90) &&
        inRange(coordinates.longitude, -180, 180) &&
        !(coordinates.latitude == 0 && coordinates.longitude == 0);
  }
}
