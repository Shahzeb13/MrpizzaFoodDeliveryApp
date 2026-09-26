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
  String toString() =>
      'CapturedCoordinates($latitude, $longitude)';
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
