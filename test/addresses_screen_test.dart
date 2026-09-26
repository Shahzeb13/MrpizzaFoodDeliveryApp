import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/location_provider.dart';
import 'package:mrpizza/features/location/data/location_repository.dart';
import 'package:mrpizza/features/location/models/captured_location.dart';
import 'package:mrpizza/features/profile/data/profile_repository.dart';
import 'package:mrpizza/features/profile/providers/profile_provider.dart';
import 'package:mrpizza/features/profile/screens/addresses_screen.dart';

import 'support/fake_location_sources.dart';

/// Records what the screen tried to save instead of writing to Supabase.
class RecordingProfileRepository extends ProfileRepository {
  String? savedLabel;
  String? savedAddressLine;
  double? savedLatitude;
  double? savedLongitude;

  @override
  Future<void> addAddress({
    required String userId,
    required String label,
    required String addressLine,
    double? latitude,
    double? longitude,
  }) async {
    savedLabel = label;
    savedAddressLine = addressLine;
    savedLatitude = latitude;
    savedLongitude = longitude;
  }
}

void main() {
  const fix = CapturedCoordinates(latitude: 34.2045, longitude: 73.24);

  late RecordingProfileRepository profileRepository;
  late FakeDeviceLocationSource deviceSource;

  Future<ProviderContainer> pumpAddressesScreen(
    WidgetTester tester, {
    String? addressText = 'Al Mansoor Town, Abbottabad',
    LocationPermissionOutcome permission = LocationPermissionOutcome.granted,
  }) async {
    profileRepository = RecordingProfileRepository();
    deviceSource = FakeDeviceLocationSource(permission: permission, fix: fix);

    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue('user-1'),
        addressesFutureProvider.overrideWith((ref) async => const []),
        profileRepositoryProvider.overrideWithValue(profileRepository),
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
        child: const MaterialApp(home: AddressesScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> openAddAddressSheet(WidgetTester tester) async {
    await tester.tap(find.text('Add New Address').last);
    await tester.pumpAndSettle();
  }

  testWidgets('no longer asks the customer to type coordinates by hand',
      (tester) async {
    await pumpAddressesScreen(tester);
    await openAddAddressSheet(tester);

    expect(find.text('Latitude (optional)'), findsNothing);
    expect(find.text('Longitude (optional)'), findsNothing);
  });

  testWidgets('filling the location fills in the address text', (tester) async {
    await pumpAddressesScreen(tester);
    await openAddAddressSheet(tester);

    await tester.tap(find.text('Use My Current Location'));
    await tester.pumpAndSettle();

    expect(find.text('Al Mansoor Town, Abbottabad'), findsOneWidget);
  });

  testWidgets('saving after a capture stores the coordinates', (tester) async {
    await pumpAddressesScreen(tester);
    await openAddAddressSheet(tester);

    await tester.tap(find.text('Use My Current Location'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Label (e.g. Home, Hostel)'), 'Home');
    await tester.tap(find.text('Save Address'));
    await tester.pumpAndSettle();

    expect(profileRepository.savedLabel, 'Home');
    expect(profileRepository.savedAddressLine, 'Al Mansoor Town, Abbottabad');
    expect(profileRepository.savedLatitude, 34.2045);
    expect(profileRepository.savedLongitude, 73.24);
  });

  testWidgets('a hand-typed address is saved without coordinates',
      (tester) async {
    await pumpAddressesScreen(tester);
    await openAddAddressSheet(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Label (e.g. Home, Hostel)'), 'Home');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Complete Address Details'),
      'House 12, Street 4',
    );
    await tester.tap(find.text('Save Address'));
    await tester.pumpAndSettle();

    expect(profileRepository.savedAddressLine, 'House 12, Street 4');
    expect(profileRepository.savedLatitude, isNull);
    expect(profileRepository.savedLongitude, isNull);
  });

  testWidgets('explains the problem and keeps the form usable when permission '
      'is denied', (tester) async {
    await pumpAddressesScreen(
      tester,
      permission: LocationPermissionOutcome.denied,
    );
    await openAddAddressSheet(tester);

    await tester.tap(find.text('Use My Current Location'));
    await tester.pumpAndSettle();

    expect(find.textContaining('permission'), findsOneWidget);

    // The customer can still type an address and save it.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Label (e.g. Home, Hostel)'), 'Home');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Complete Address Details'),
      'House 12, Street 4',
    );
    await tester.tap(find.text('Save Address'));
    await tester.pumpAndSettle();

    expect(profileRepository.savedAddressLine, 'House 12, Street 4');
  });

  testWidgets('offers a settings button when permission is blocked forever',
      (tester) async {
    await pumpAddressesScreen(
      tester,
      permission: LocationPermissionOutcome.deniedForever,
    );
    await openAddAddressSheet(tester);

    await tester.tap(find.text('Use My Current Location'));
    await tester.pumpAndSettle();

    expect(find.text('Open Settings'), findsOneWidget);

    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();

    expect(deviceSource.settingsOpened, isTrue);
  });
}
