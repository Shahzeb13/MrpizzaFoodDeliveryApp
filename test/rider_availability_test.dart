import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/rider/models/rider_availability.dart';

void main() {
  test('reads the three statuses the database allows', () {
    expect(riderAvailabilityFromDatabaseValue('offline'),
        RiderAvailability.offline);
    expect(riderAvailabilityFromDatabaseValue('available'),
        RiderAvailability.available);
    expect(riderAvailabilityFromDatabaseValue('on_delivery'),
        RiderAvailability.onDelivery);
  });

  test('an unknown or missing status is offline, never available', () {
    expect(riderAvailabilityFromDatabaseValue(null),
        RiderAvailability.offline);
    expect(riderAvailabilityFromDatabaseValue(''), RiderAvailability.offline);
    expect(riderAvailabilityFromDatabaseValue('on-delivery'),
        RiderAvailability.offline);
  });

  test('casing and padding do not change the reading', () {
    expect(riderAvailabilityFromDatabaseValue('  AVAILABLE '),
        RiderAvailability.available);
  });

  test('round trips through the database value', () {
    for (final availability in RiderAvailability.values) {
      if (availability == RiderAvailability.onDelivery) continue;
      expect(
        riderAvailabilityFromDatabaseValue(
            riderAvailabilityToDatabaseValue(availability)),
        availability,
      );
    }
  });

  test('on_delivery cannot be sent to the database, only set by a transition', () {
    expect(
      () => riderAvailabilityToDatabaseValue(RiderAvailability.onDelivery),
      throwsUnsupportedError,
    );
  });
}
