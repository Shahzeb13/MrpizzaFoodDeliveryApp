import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/location_provider.dart';
import 'package:mrpizza/features/location/data/location_repository.dart';
import 'package:mrpizza/features/location/models/captured_location.dart';
import 'package:mrpizza/features/profile/models/profile.dart';
import 'package:mrpizza/features/profile/providers/profile_provider.dart';
import 'package:mrpizza/widgets/shared_components.dart';

import 'support/fake_location_sources.dart';

void main() {
  const fix = CapturedCoordinates(latitude: 34.2045, longitude: 73.24);

  late FakeDeviceLocationSource deviceSource;

  Future<ProviderContainer> pumpDialog(
    WidgetTester tester, {
    required List<UserAddress> savedAddresses,
    LocationPermissionOutcome permission = LocationPermissionOutcome.granted,
    String? addressText = 'Al Mansoor Town, Abbottabad',
  }) async {
    deviceSource = FakeDeviceLocationSource(permission: permission, fix: fix);

    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue('user-1'),
        addressesFutureProvider.overrideWith((ref) async => savedAddresses),
        locationRepositoryProvider.overrideWithValue(
          LocationRepository(
            deviceSource: deviceSource,
            addressLookup: FakeAddressTextLookup(result: addressText),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LocationSelectionDialog()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('offers the addresses the customer actually saved', (tester) async {
    await pumpDialog(
      tester,
      savedAddresses: const [
        UserAddress(
          id: 'addr-1',
          userId: 'user-1',
          label: 'Home',
          addressLine: 'House 12, Street 4, Abbottabad',
        ),
      ],
    );

    await tester.tap(find.byType(DropdownButtonFormField<UserAddress>));
    await tester.pumpAndSettle();

    expect(find.text('House 12, Street 4, Abbottabad'), findsOneWidget);
  });

  testWidgets('never offers made-up addresses', (tester) async {
    await pumpDialog(tester, savedAddresses: const []);

    expect(find.text('COMSATS Abbottabad, Phase 2'), findsNothing);
    expect(find.text('Mansehra University Road'), findsNothing);
    expect(find.text('Supply Bazaar, Mansehra'), findsNothing);
  });

  testWidgets('hides the saved-address list when there are none',
      (tester) async {
    await pumpDialog(tester, savedAddresses: const []);

    expect(find.text('Saved address'), findsNothing);
  });

  testWidgets('picking a saved address keeps its coordinates', (tester) async {
    final container = await pumpDialog(
      tester,
      savedAddresses: const [
        UserAddress(
          id: 'addr-1',
          userId: 'user-1',
          label: 'Home',
          addressLine: 'House 12, Street 4, Abbottabad',
          latitude: 34.21,
          longitude: 73.25,
        ),
      ],
    );

    await tester.tap(find.byType(DropdownButtonFormField<UserAddress>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('House 12, Street 4, Abbottabad').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm Location'));
    await tester.pumpAndSettle();

    final state = container.read(locationProvider);
    expect(state.address, 'House 12, Street 4, Abbottabad');
    expect(state.latitude, 34.21);
    expect(state.longitude, 73.25);
  });

  testWidgets('using the current location stores the captured pin',
      (tester) async {
    final container = await pumpDialog(tester, savedAddresses: const []);

    await tester.tap(find.text('Use Current Location'));
    await tester.pumpAndSettle();

    final state = container.read(locationProvider);
    expect(state.address, 'Al Mansoor Town, Abbottabad');
    expect(state.latitude, 34.2045);
  });

  testWidgets('shows the problem and stays open when permission is denied',
      (tester) async {
    final container = await pumpDialog(
      tester,
      savedAddresses: const [],
      permission: LocationPermissionOutcome.denied,
    );

    await tester.tap(find.text('Use Current Location'));
    await tester.pumpAndSettle();

    expect(find.textContaining('permission'), findsOneWidget);
    expect(container.read(locationProvider).hasCoordinates, isFalse);
  });

  testWidgets('offers a settings button when permission is blocked forever',
      (tester) async {
    await pumpDialog(
      tester,
      savedAddresses: const [],
      permission: LocationPermissionOutcome.deniedForever,
    );

    await tester.tap(find.text('Use Current Location'));
    await tester.pumpAndSettle();

    expect(find.text('Open Settings'), findsOneWidget);

    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();

    expect(deviceSource.settingsOpened, isTrue);
  });
}
