import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/location/data/location_repository.dart';
import 'package:mrpizza/features/location/models/captured_location.dart';

import 'support/fake_location_sources.dart';

void main() {
  const fix = CapturedCoordinates(latitude: 34.2045, longitude: 73.24);

  group('LocationRepository permission handling', () {
    test('asks the user to allow location when permission is denied', () async {
      final source = FakeDeviceLocationSource(
        permission: LocationPermissionOutcome.denied,
      );
      final repository = LocationRepository(
        deviceSource: source,
        addressLookup: FakeAddressTextLookup(result: 'Al Mansoor Town'),
      );

      await expectLater(
        repository.captureCurrentLocation(),
        throwsA(
          isA<LocationCaptureException>()
              .having((e) => e.settingsMustBeOpened, 'settingsMustBeOpened', isFalse)
              .having((e) => e.message, 'message', contains('permission')),
        ),
      );
    });

    test('tells the user to open settings when permission is blocked forever',
        () async {
      final source = FakeDeviceLocationSource(
        permission: LocationPermissionOutcome.deniedForever,
      );
      final repository = LocationRepository(
        deviceSource: source,
        addressLookup: FakeAddressTextLookup(result: 'Al Mansoor Town'),
      );

      await expectLater(
        repository.captureCurrentLocation(),
        throwsA(
          isA<LocationCaptureException>()
              .having((e) => e.settingsMustBeOpened, 'settingsMustBeOpened', isTrue),
        ),
      );
    });

    test('can open the app settings page for the user', () async {
      final source = FakeDeviceLocationSource(
        permission: LocationPermissionOutcome.deniedForever,
      );
      final repository = LocationRepository(
        deviceSource: source,
        addressLookup: FakeAddressTextLookup(),
      );

      await repository.openAppSettings();

      expect(source.settingsOpened, isTrue);
    });
  });

  group('LocationRepository coordinate handling', () {
    test('returns the fix with the looked-up address text', () async {
      final repository = LocationRepository(
        deviceSource: FakeDeviceLocationSource(fix: fix),
        addressLookup: FakeAddressTextLookup(result: 'Al Mansoor Town'),
      );

      final captured = await repository.captureCurrentLocation();

      expect(captured.latitude, 34.2045);
      expect(captured.longitude, 73.24);
      expect(captured.addressLine, 'Al Mansoor Town');
    });

    test('keeps the pin when the address lookup fails', () async {
      final repository = LocationRepository(
        deviceSource: FakeDeviceLocationSource(fix: fix),
        addressLookup: FakeAddressTextLookup(error: Exception('no network')),
      );

      final captured = await repository.captureCurrentLocation();

      expect(captured.latitude, 34.2045);
      expect(captured.addressLine, isEmpty);
    });

    test('keeps the pin when the address lookup finds nothing', () async {
      final repository = LocationRepository(
        deviceSource: FakeDeviceLocationSource(fix: fix),
        addressLookup: FakeAddressTextLookup(result: null),
      );

      final captured = await repository.captureCurrentLocation();

      expect(captured.addressLine, isEmpty);
    });

    test('rejects a null island fix as a failed capture', () async {
      final repository = LocationRepository(
        deviceSource: FakeDeviceLocationSource(
          fix: const CapturedCoordinates(latitude: 0, longitude: 0),
        ),
        addressLookup: FakeAddressTextLookup(result: 'Nowhere'),
      );

      await expectLater(
        repository.captureCurrentLocation(),
        throwsA(isA<LocationCaptureException>()),
      );
    });

    test('turns a device failure into a capturable message', () async {
      final repository = LocationRepository(
        deviceSource: FakeDeviceLocationSource(
          fixError: Exception('location services are off'),
        ),
        addressLookup: FakeAddressTextLookup(),
      );

      await expectLater(
        repository.captureCurrentLocation(),
        throwsA(
          isA<LocationCaptureException>().having(
            (e) => e.message,
            'message',
            contains('location services are off'),
          ),
        ),
      );
    });
  });
}
