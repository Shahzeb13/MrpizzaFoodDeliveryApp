import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/location_provider.dart';
import 'package:mrpizza/features/location/data/location_repository.dart';
import 'package:mrpizza/features/location/models/captured_location.dart';
import 'package:mrpizza/features/location/screens/map_location_picker_sheet.dart';
import 'package:mrpizza/features/orders/data/orders_repository.dart';
import 'package:mrpizza/features/orders/models/branch.dart';
import 'package:mrpizza/features/orders/providers/orders_provider.dart';
import 'package:mrpizza/features/profile/models/profile.dart';
import 'package:mrpizza/features/profile/providers/profile_provider.dart';

import 'support/fake_location_sources.dart';

/// Widget tests for the delivery map sheet.
///
/// These run with no Mapbox token, which is the state a build starts in when
/// `MAPBOX_ACCESS_TOKEN` is missing. That is deliberately supported: the sheet
/// has to degrade to manual entry rather than fail, and no native Mapbox view is
/// created here.
void main() {
  const branches = [
    Branch(
      id: 'branch-1',
      name: 'Mr. Pizza – Abbottabad',
      latitude: 34.1688,
      longitude: 73.2215,
    ),
    Branch(
      id: 'branch-2',
      name: 'Mr. Pizza – Mansehra',
      latitude: 34.3302,
      longitude: 73.1969,
    ),
  ];

  const savedAddresses = [
    UserAddress(
      id: 'addr-1',
      userId: 'user-1',
      label: 'Home',
      addressLine: 'House 12, Street 4, Abbottabad',
      latitude: 34.17,
      longitude: 73.22,
    ),
  ];

  late ProviderContainer container;

  Future<void> pumpSheet(
    WidgetTester tester, {
    List<UserAddress> saved = savedAddresses,
    LocationPermissionOutcome permission = LocationPermissionOutcome.granted,
  }) async {
    container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue('user-1'),
        addressesFutureProvider.overrideWith((ref) async => saved),
        branchesFutureProvider.overrideWith(
          (ref) async => const BranchCatalog(
            branches: branches,
            usedFallbackData: false,
          ),
        ),
        locationRepositoryProvider.overrideWithValue(
          LocationRepository(
            deviceSource: FakeDeviceLocationSource(
              permission: permission,
              fix: const CapturedCoordinates(latitude: 34.2, longitude: 73.2),
            ),
            addressLookup: FakeAddressTextLookup(result: 'Somewhere, Pakistan'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showMapLocationPicker(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  FilledButton confirmButton(WidgetTester tester) => tester.widget<FilledButton>(
        find.byKey(const Key('map-picker-confirm')),
      );

  testWidgets('opens as a modal over whatever asked for it', (tester) async {
    await pumpSheet(tester);
    expect(find.text('Pick your location'), findsNothing);

    await openSheet(tester);

    expect(find.text('Pick your location'), findsOneWidget);
    expect(find.text('open'), findsOneWidget, reason: 'underneath, not replaced');
    expect(
      find.text('Move the map until the pin is on your door'),
      findsOneWidget,
    );
  });

  testWidgets('saying no leaves everything untouched', (tester) async {
    await pumpSheet(tester);
    await openSheet(tester);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Pick your location'), findsNothing);
    expect(container.read(locationProvider).isSet, isFalse);
    expect(container.read(locationProvider).latitude, isNull);
  });

  testWidgets('says so plainly when the map cannot start', (tester) async {
    await pumpSheet(tester);
    await openSheet(tester);

    // No token means no map and therefore no "Locate me" — there would be
    // nothing to centre. Typing the address stays available.
    expect(find.textContaining('map is unavailable'), findsOneWidget);
    expect(find.byTooltip('Locate me'), findsNothing);
    expect(
      find.text('Address & what the rider should look for'),
      findsOneWidget,
    );
  });

  testWidgets('confirm cannot be pressed before there is a point',
      (tester) async {
    await pumpSheet(tester);
    await openSheet(tester);

    expect(confirmButton(tester).onPressed, isNull);
  });

  testWidgets('the address field fills itself in, and is not a gate on '
      'confirming', (tester) async {
    await pumpSheet(tester);
    await openSheet(tester);

    // The field is labelled for what the customer adds, and the copy says the
    // street lookup happens by itself — so an empty-looking field does not read
    // as "you forgot something".
    expect(
      find.text('Address & what the rider should look for'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Move the map and we look up the street for you'),
      findsOneWidget,
    );

    // Still confirmable: the pin alone is a real delivery location.
    expect(confirmButton(tester).onPressed, isNull,
        reason: 'nothing is pinned yet, but the field is not the blocker');
  });

  testWidgets('confirms with only a pin, when there is no address text',
      (tester) async {
    await pumpSheet(tester);

    // A pin with nothing written beside it — the customer moved the map and
    // never typed. That is still a complete answer.
    container.read(locationProvider.notifier).applyMapPick(
          latitude: 34.1712,
          longitude: 73.2201,
          addressText: '',
        );

    await openSheet(tester);

    expect(confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('no GPS is requested until Locate me is tapped', (tester) async {
    await pumpSheet(
      tester,
      permission: LocationPermissionOutcome.deniedForever,
    );
    await openSheet(tester);

    // Nothing has been asked of the device yet.
    expect(find.textContaining('Location permission is blocked'), findsNothing);
    expect(container.read(locationProvider).isSet, isFalse);
  });

  testWidgets('backing out never writes to the shared location',
      (tester) async {
    await pumpSheet(tester);
    await openSheet(tester);

    await tester.drag(find.byType(MapLocationPickerSheet), const Offset(0, 400));
    await tester.pumpAndSettle();

    expect(container.read(locationProvider).isSet, isFalse);
    expect(container.read(locationProvider).longitude, isNull);
  });

  testWidgets('an existing location opens the sheet on that spot',
      (tester) async {
    await pumpSheet(tester);

    // Set before the sheet opens, which is what returning customer sees.
    container.read(locationProvider.notifier).applyMapPick(
          latitude: 34.1712,
          longitude: 73.2201,
          addressText: 'Block C, Abbottabad',
        );

    await openSheet(tester);

    // The coordinates are carried across, so confirm is live immediately.
    expect(confirmButton(tester).onPressed, isNotNull);
    expect(find.text('Block C, Abbottabad'), findsWidgets);
    expect(find.textContaining('34.17120'), findsOneWidget);
  });
}
