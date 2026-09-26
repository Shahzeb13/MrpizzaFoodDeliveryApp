import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/location_provider.dart';
import 'package:mrpizza/features/location/data/location_repository.dart';
import 'package:mrpizza/features/location/models/captured_location.dart';
import 'package:mrpizza/features/profile/models/profile.dart';

import 'support/fake_location_sources.dart';

void main() {
  const fix = CapturedCoordinates(latitude: 34.2045, longitude: 73.24);

  /// Builds a notifier over a fake GPS, returning both so the test can assert
  /// on the fake's side effects too.
  (LocationNotifier, FakeDeviceLocationSource) buildNotifier({
    LocationPermissionOutcome permission = LocationPermissionOutcome.granted,
    Object? fixError,
    String? addressText = 'Al Mansoor Town, Abbottabad',
  }) {
    final deviceSource = FakeDeviceLocationSource(
      permission: permission,
      fix: fix,
      fixError: fixError,
    );
    final notifier = LocationNotifier(
      repository: LocationRepository(
        deviceSource: deviceSource,
        addressLookup: FakeAddressTextLookup(result: addressText),
      ),
    );
    return (notifier, deviceSource);
  }

  test('starts with no address and no captured pin', () {
    final (notifier, _) = buildNotifier();

    final state = notifier.build();

    expect(state.address, isEmpty);
    expect(state.isSet, isFalse);
    expect(state.latitude, isNull);
    expect(state.longitude, isNull);
    expect(state.isCapturing, isFalse);
    expect(state.errorMessage, isNull);
    expect(state.settingsMustBeOpened, isFalse);
  });

  group('useCurrentLocation', () {
    test('stores the captured address and coordinates', () async {
      final (notifier, _) = buildNotifier();

      await notifier.useCurrentLocation();

      expect(notifier.state.address, 'Al Mansoor Town, Abbottabad');
      expect(notifier.state.isSet, isTrue);
      expect(notifier.state.latitude, 34.2045);
      expect(notifier.state.longitude, 73.24);
      expect(notifier.state.errorMessage, isNull);
    });

    test('reports progress while the GPS fix is being taken', () async {
      final (notifier, _) = buildNotifier();

      final pending = notifier.useCurrentLocation();
      expect(notifier.state.isCapturing, isTrue);

      await pending;
      expect(notifier.state.isCapturing, isFalse);
    });

    test('keeps the pin but leaves the text empty when lookup finds nothing',
        () async {
      final (notifier, _) = buildNotifier(addressText: null);

      await notifier.useCurrentLocation();

      expect(notifier.state.latitude, 34.2045);
      expect(notifier.state.address, isEmpty);
      expect(notifier.state.errorMessage, isNull);
    });

    test('shows a message and no pin when permission is denied', () async {
      final (notifier, _) =
          buildNotifier(permission: LocationPermissionOutcome.denied);

      await notifier.useCurrentLocation();

      expect(notifier.state.errorMessage, contains('permission'));
      expect(notifier.state.settingsMustBeOpened, isFalse);
      expect(notifier.state.isCapturing, isFalse);
      expect(notifier.state.latitude, isNull);
      expect(notifier.state.isSet, isFalse);
    });

    test('flags that settings must be opened when permission is blocked',
        () async {
      final (notifier, _) =
          buildNotifier(permission: LocationPermissionOutcome.deniedForever);

      await notifier.useCurrentLocation();

      expect(notifier.state.settingsMustBeOpened, isTrue);
    });

    test('clears a previous error once a capture succeeds', () async {
      final (failing, _) =
          buildNotifier(permission: LocationPermissionOutcome.denied);
      await failing.useCurrentLocation();
      expect(failing.state.errorMessage, isNotNull);

      final (working, _) = buildNotifier();
      await working.useCurrentLocation();

      expect(working.state.errorMessage, isNull);
    });

    test('turns a GPS failure into a readable message', () async {
      final (notifier, _) = buildNotifier(fixError: Exception('GPS timeout'));

      await notifier.useCurrentLocation();

      expect(notifier.state.errorMessage, contains('GPS timeout'));
      expect(notifier.state.isCapturing, isFalse);
    });
  });

  group('setLocation', () {
    test('records a typed address as set', () {
      final (notifier, _) = buildNotifier();

      notifier.setLocation('House 12, Street 4, Abbottabad');

      expect(notifier.state.address, 'House 12, Street 4, Abbottabad');
      expect(notifier.state.isSet, isTrue);
    });

    test('drops a stale GPS pin so the branch match stays honest', () async {
      final (notifier, _) = buildNotifier();
      await notifier.useCurrentLocation();
      expect(notifier.state.latitude, 34.2045);

      notifier.setLocation('Somewhere else entirely');

      expect(notifier.state.latitude, isNull);
      expect(notifier.state.longitude, isNull);
    });

    test('clears a previous error message', () {
      final (notifier, _) = buildNotifier();
      notifier.setLocation('first');

      notifier.setLocation('second');

      expect(notifier.state.address, 'second');
      expect(notifier.state.errorMessage, isNull);
    });
  });

  test('openAppSettings reaches the device settings page', () async {
    final (notifier, deviceSource) =
        buildNotifier(permission: LocationPermissionOutcome.deniedForever);

    await notifier.openAppSettings();

    expect(deviceSource.settingsOpened, isTrue);
  });

  group('applySavedAddress', () {
    test('keeps the coordinates stored with a saved address', () {
      final (notifier, _) = buildNotifier();

      notifier.applySavedAddress(const UserAddress(
        id: 'addr-1',
        userId: 'user-1',
        label: 'Home',
        addressLine: 'House 12, Street 4, Abbottabad',
        latitude: 34.21,
        longitude: 73.25,
      ));

      expect(notifier.state.address, 'House 12, Street 4, Abbottabad');
      expect(notifier.state.latitude, 34.21);
      expect(notifier.state.longitude, 73.25);
      expect(notifier.state.isSet, isTrue);
    });

    test('accepts a saved address that has no pin', () {
      final (notifier, _) = buildNotifier();

      notifier.applySavedAddress(const UserAddress(
        id: 'addr-2',
        userId: 'user-1',
        label: 'Home',
        addressLine: 'House 12, Street 4',
      ));

      expect(notifier.state.address, 'House 12, Street 4');
      expect(notifier.state.hasCoordinates, isFalse);
    });

    test('replaces a previous pin rather than keeping both', () {
      final (notifier, _) = buildNotifier();

      notifier.applySavedAddress(const UserAddress(
        id: 'addr-1',
        userId: 'user-1',
        label: 'Home',
        addressLine: 'Pinned place',
        latitude: 34.21,
        longitude: 73.25,
      ));
      notifier.applySavedAddress(const UserAddress(
        id: 'addr-2',
        userId: 'user-1',
        label: 'Work',
        addressLine: 'Unpinned place',
      ));

      expect(notifier.state.address, 'Unpinned place');
      expect(notifier.state.latitude, isNull);
      expect(notifier.state.longitude, isNull);
    });
  });

  group('locationProvider', () {
    test('builds a notifier backed by the real repository', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(locationProvider.notifier);

      expect(notifier.state.isSet, isFalse);
      expect(notifier.state.address, isEmpty);
    });
  });
}
