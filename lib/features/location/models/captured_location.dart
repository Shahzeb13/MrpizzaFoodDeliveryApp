/// A latitude/longitude pair captured from the device GPS.
class CapturedCoordinates {
  final double latitude;
  final double longitude;

  const CapturedCoordinates({required this.latitude, required this.longitude});

  @override
  bool operator ==(Object other) =>
      other is CapturedCoordinates &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'CapturedCoordinates($latitude, $longitude)';

  /// Whether a latitude/longitude pair can describe a real place on Earth.
  ///
  /// `0,0` sits in the Gulf of Guinea and is what a device reports when it has
  /// no fix at all, so it is rejected alongside out-of-range and NaN values.
  /// Shared by the GPS capture and by the map picker, so a position chosen on
  /// screen is held to exactly the same rule as one read from the sensor.
  static bool isPlausibleEarth(double latitude, double longitude) {
    bool inRange(double value, double min, double max) =>
        value >= min && value <= max && !value.isNaN;

    if (!inRange(latitude, -90, 90)) return false;
    if (!inRange(longitude, -180, 180)) return false;
    return !(latitude == 0 && longitude == 0);
  }
}

/// The result of a successful "use my location" capture.
///
/// [addressLine] is a human-readable street address derived from the
/// coordinates. It is empty when the reverse lookup failed or found nothing —
/// the coordinates are still valid, and the user can type the address
/// themselves, so a failed lookup never discards a good GPS fix.
class CapturedAddress {
  final double latitude;
  final double longitude;
  final String addressLine;

  const CapturedAddress({
    required this.latitude,
    required this.longitude,
    required this.addressLine,
  });

  /// True when a street address was found for these coordinates.
  bool get hasAddressText => addressLine.trim().isNotEmpty;
}
