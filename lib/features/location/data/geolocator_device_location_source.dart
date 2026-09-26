import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/captured_location.dart';
import 'location_repository.dart';

/// Reads real device positions through the `geolocator` plugin.
///
/// This is the only class that talks to the plugin, so the rest of the app (and
/// every test) works against the [DeviceLocationSource] interface instead.
class GeolocatorDeviceLocationSource implements DeviceLocationSource {
  /// How long to wait for a GPS fix before giving up and letting the customer
  /// type their address instead.
  static const Duration fixTimeout = Duration(seconds: 15);

  @override
  Future<LocationPermissionOutcome> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationCaptureException(
        'Location services are turned off on this device. Turn them on, or '
        'type your address instead.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    switch (permission) {
      case LocationPermission.denied:
        return LocationPermissionOutcome.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionOutcome.deniedForever;
      case LocationPermission.unableToDetermine:
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return LocationPermissionOutcome.granted;
    }
  }

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<CapturedCoordinates> readCurrentCoordinates() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: fixTimeout,
      ),
    ).timeout(fixTimeout);

    return CapturedCoordinates(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}
