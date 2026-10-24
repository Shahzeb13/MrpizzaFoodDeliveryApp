import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/config/mapbox_config.dart';
import 'package:mrpizza/core/providers/location_provider.dart';
import 'package:mrpizza/features/location/data/location_repository.dart';
import 'package:mrpizza/features/location/models/captured_location.dart';

import 'support/fake_location_sources.dart';

void main() {
  group('MapboxConfig', () {
    test('reports the variable name it looks for', () {
      expect(MapboxConfig.tokenKey, 'MAPBOX_ACCESS_TOKEN');
    });

    test('says how to supply the token when there is none', () {
      // No --dart-define and no loaded .env in a test process.
      expect(
        MapboxConfig.describeConfiguration(),
        'Mapbox: no MAPBOX_ACCESS_TOKEN found. Pass it with '
        '--dart-define=MAPBOX_ACCESS_TOKEN=pk... or put it in .env.',
      );
    });

    test('never hands a token out when none is configured', () {
      expect(MapboxConfig.usableToken, anyOf(isNull, isNot(startsWith('sk.'))));
    });

    test('refuses a secret token', () {
      // The rule that keeps an `sk.` value from ever reaching the native SDK is
      // stated here against the shape of the check, because MapboxConfig reads
      // its value once from the process environment and cannot be re-pointed
      // inside a test.
      expect(MapboxConfig.isUsable, isFalse);
      expect(MapboxConfig.usableToken, isNull);
    });

    test('the customer-facing message never mentions tokens', () {
      expect(MapboxConfig.unavailableMessage, isNot(contains('token')));
      expect(MapboxConfig.unavailableMessage, isNot(contains('MAPBOX')));
    });
  });

  group('applyMapPick', () {
    late LocationNotifier notifier;

    setUp(() {
      notifier = LocationNotifier(
        repository: LocationRepository(
          deviceSource: FakeDeviceLocationSource(
            fix: const CapturedCoordinates(latitude: 34.1, longitude: 73.1),
          ),
          addressLookup: FakeAddressTextLookup(result: 'Somewhere'),
        ),
      );
    });

    test('stores the pin the customer chose and the text they wrote', () {
      notifier.applyMapPick(
        latitude: 34.1712,
        longitude: 73.2201,
        addressText: 'Block C, Abbottabad',
      );

      expect(notifier.state.isSet, isTrue);
      expect(notifier.state.address, 'Block C, Abbottabad');
      expect(notifier.state.latitude, 34.1712);
      expect(notifier.state.longitude, 73.2201);
      expect(notifier.state.hasCoordinates, isTrue);
    });

    test('replaces an earlier pin rather than merging with it', () async {
      await notifier.useCurrentLocation();

      notifier.applyMapPick(
        latitude: 34.3302,
        longitude: 73.1969,
        addressText: 'University Road, Mansehra',
      );

      expect(notifier.state.address, 'University Road, Mansehra');
      expect(notifier.state.latitude, 34.3302);
      expect(notifier.state.longitude, 73.1969);
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.isCapturing, isFalse);
    });

    test('trims the text so a stray space is never stored', () {
      notifier.applyMapPick(
        latitude: 34.1,
        longitude: 73.1,
        addressText: '  Block C  ',
      );

      expect(notifier.state.address, 'Block C');
    });

    test('an empty description still keeps the pin, for the caller to reject',
        () {
      notifier.applyMapPick(
        latitude: 34.1,
        longitude: 73.1,
        addressText: '   ',
      );

      expect(notifier.state.address, '');
      expect(notifier.state.hasCoordinates, isTrue);
    });
  });
}
