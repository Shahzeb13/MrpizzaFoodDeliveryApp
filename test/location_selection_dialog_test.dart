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

    // Two, not one: the dialog now opens with the default already preselected,
    // so the collapsed button shows the address AND the opened menu lists it.
    // The point of this test is that only genuinely saved addresses appear —
    // which "never offers made-up addresses" covers.
    expect(find.text('House 12, Street 4, Abbottabad'), findsNWidgets(2));
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

  testWidgets('handles duplicate saved addresses gracefully without throwing dropdown assertion', (tester) async {
    await pumpDialog(
      tester,
      savedAddresses: const [
        UserAddress(
          id: 'addr-1',
          userId: 'user-1',
          label: 'Home',
          addressLine: 'House 12, Street 4, Abbottabad',
        ),
        UserAddress(
          id: 'addr-1',
          userId: 'user-1',
          label: 'Home Duplicate',
          addressLine: 'House 12, Street 4, Abbottabad',
        ),
      ],
    );

    await tester.tap(find.byType(DropdownButtonFormField<UserAddress>));
    await tester.pumpAndSettle();

    // One preselected in the button, one in the opened menu — and NOT three.
    // The point is that the two rows sharing an id collapse into a single
    // choice, so a duplicate can never be selected as something new.
    expect(find.text('House 12, Street 4, Abbottabad'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rebuilding dialog after selecting saved address does not crash dropdown', (tester) async {
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
    await tester.tap(find.text('House 12, Street 4, Abbottabad').last);
    await tester.pumpAndSettle();

    // Trigger an extra rebuild
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('confirming does not require picking anything first', () {
    // The regression this whole group is about. The dialog opened with nothing
    // selected and `_select` returned early when both the text field and the
    // dropdown were empty — so "Confirm Location" was a dead button and the only
    // way through was opening the dropdown and choosing something on every
    // visit, including the ones where the customer had already marked a default.
    UserAddress home({required String id, required String line, bool isDefault = false}) {
      return UserAddress(
        id: id,
        userId: 'user-1',
        label: 'Home',
        addressLine: line,
        isDefault: isDefault,
      );
    }

    testWidgets('the marked default is already filled in', (tester) async {
      await pumpDialog(
        tester,
        savedAddresses: [
          home(id: 'addr-1', line: 'Office, Blue Area'),
          home(id: 'addr-2', line: 'House 12, Street 4', isDefault: true),
        ],
      );

      // Visible in the collapsed button without ever being tapped.
      expect(find.text('House 12, Street 4'), findsOneWidget);
      expect(find.text('Saved address'), findsNothing);
    });

    testWidgets('confirming on its own applies the default', (tester) async {
      final container = await pumpDialog(
        tester,
        savedAddresses: [
          home(id: 'addr-1', line: 'Office, Blue Area'),
          home(id: 'addr-2', line: 'House 12, Street 4', isDefault: true),
        ],
      );

      await tester.tap(find.text('Confirm Location'));
      await tester.pumpAndSettle();

      expect(
        container.read(locationProvider).address,
        'House 12, Street 4',
      );
    });

    testWidgets('the only saved address works too', (tester) async {
      final container = await pumpDialog(
        tester,
        savedAddresses: [home(id: 'addr-1', line: 'House 12, Street 4')],
      );

      await tester.tap(find.text('Confirm Location'));
      await tester.pumpAndSettle();

      expect(
        container.read(locationProvider).address,
        'House 12, Street 4',
      );
    });

    testWidgets('with no saved address the button still does nothing safely',
        (tester) async {
      // Nobody is fooled into an empty delivery address.
      final container = await pumpDialog(tester, savedAddresses: const []);

      await tester.tap(find.text('Confirm Location'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Blank, not invented. Nobody is fooled into an empty delivery address.
      expect(container.read(locationProvider).address, isEmpty);
    });
  });
}
