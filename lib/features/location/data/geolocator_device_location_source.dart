import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/captured_location.dart';
import 'location_repository.dart';

/// Reads real device positions through the `geolocator` plugin.
///
/// This is the only class that talks to the plugin, so the rest of the app (and
/// every test) works against the [DeviceLocationSource] interface instead.
class GeolocatorDeviceLocationSource implements DeviceLocationSource {
  /// How long to wait for a live GPS fix before giving up and letting the
  /// customer pick their spot on the map instead.
  static const Duration fixTimeout = Duration(seconds: 15);

  /// How stale a cached position may be and still be offered. Android keeps a
  /// last-known fix from any recent location request and hands it over for
  /// free, which is the difference between the map moving instantly and the
  /// customer staring at a spinner indoors.
  static const Duration lastKnownMaxAge = Duration(minutes: 10);

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
    // The cached fix first. It costs nothing, it is usually seconds old, and
    // for "centre the map roughly on me" it is more than good enough — the
    // customer drags the pin to their door afterwards anyway.
    final cached = await readLastKnownCoordinates();
    if (cached != null) return cached;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // Medium rather than high. High forces a raw GPS lock, which is the
          // slowest thing on the planet and routinely never completes
          // indoors or in an urban canyon — it would always time out. Medium
          // lets the device use its network and sensor fusion, and the pin
          // absorbs the remaining imprecision.
          accuracy: LocationAccuracy.medium,
          timeLimit: fixTimeout,
        ),
      ).timeout(fixTimeout);

      return CapturedCoordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } on TimeoutException {
      // A fix often lands in the same breath as the timeout being raised.
      final late = await readLastKnownCoordinates();
      if (late != null) return late;
      rethrow;
    } on LocationServiceDisabledException {
      rethrow;
    }
  }

  /// The device's cached position, or null when there is none, it is too old,
  /// or the platform will not say.
  ///
  /// Never throws: a failure here just means "no shortcut available".
  Future<CapturedCoordinates?> readLastKnownCoordinates() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) return null;
      if (DateTime.now().difference(last.timestamp) > lastKnownMaxAge) {
        return null;
      }
      return CapturedCoordinates(
        latitude: last.latitude,
        longitude: last.longitude,
      );
    } catch (_) {
      return null;
    }
  }
}
