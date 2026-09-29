/// The `rider_details.status` values the database allows.
enum RiderAvailability {
  offline,
  available,
  onDelivery,
}

/// Reads the `rider_details.status` column.
///
/// Anything unrecognised is [RiderAvailability.offline] rather than
/// [RiderAvailability.available]: if the status is unreadable the safe answer
/// is "this rider is not taking work", never "accept more work".
RiderAvailability riderAvailabilityFromDatabaseValue(String? rawStatus) {
  switch (rawStatus?.trim().toLowerCase()) {
    case 'available':
      return RiderAvailability.available;
    case 'on_delivery':
      return RiderAvailability.onDelivery;
    default:
      return RiderAvailability.offline;
  }
}

/// The value to send to `rider_set_availability`.
///
/// Throws for [RiderAvailability.onDelivery]: the database refuses that value on
/// purpose, because only the lifecycle functions may put a rider on delivery.
/// Returning the string would have let a caller send something the database
/// always rejects, and a round-trip test would have blessed it.
String riderAvailabilityToDatabaseValue(RiderAvailability availability) {
  switch (availability) {
    case RiderAvailability.offline:
      return 'offline';
    case RiderAvailability.available:
      return 'available';
    case RiderAvailability.onDelivery:
      throw UnsupportedError(
        'on_delivery is set by the lifecycle functions only',
      );
  }
}
