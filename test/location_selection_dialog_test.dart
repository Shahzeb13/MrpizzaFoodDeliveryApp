import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('offers the addresses the customer actually saved',
      (tester) async {
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

    await tester.tap(find.byKey(const Key(SavedAddressPickerField.fieldKey)));
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

    await tester.tap(find.byKey(const Key(SavedAddressPickerField.fieldKey)));
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

  testWidgets(
      'handles duplicate saved addresses gracefully without throwing dropdown assertion',
      (tester) async {
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

    await tester.tap(find.byKey(const Key(SavedAddressPickerField.fieldKey)));
    await tester.pumpAndSettle();

    // One preselected in the button, one in the opened menu — and NOT three.
    // The point is that the two rows sharing an id collapse into a single
    // choice, so a duplicate can never be selected as something new.
    expect(find.text('House 12, Street 4, Abbottabad'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'rebuilding dialog after selecting saved address does not crash dropdown',
      (tester) async {
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

    await tester.tap(find.byKey(const Key(SavedAddressPickerField.fieldKey)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('House 12, Street 4, Abbottabad').last);
    await tester.pumpAndSettle();

    // Trigger an extra rebuild
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('small screens', () {
    // The reported bug: a long address was clipped because the dialog had less
    // room than the text needed. Small viewports are where that shows up first,
    // so the address is re-checked at a phone size nothing larger than a
    // budget device would give it.
    const longAddress =
        'House 12B, Street 4, Near Green Valley Colony, Abbottabad Cantonment, '
        'Khyber Pakhtunkhwa';

    Future<void> pumpOnSmallScreen(
      WidgetTester tester, {
      Size size = const Size(320, 480),
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpDialog(
        tester,
        savedAddresses: const [
          UserAddress(
            id: 'addr-1',
            userId: 'user-1',
            label: 'Home',
            addressLine: longAddress,
            isDefault: true,
          ),
        ],
      );
    }

    testWidgets('renders a long address without overflowing', (tester) async {
      await pumpOnSmallScreen(tester);

      expect(find.text(longAddress), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every action stays reachable by scrolling', (tester) async {
      await pumpOnSmallScreen(tester);

      // The confirm button is the last thing in the dialog, so on a 480pt-tall
      // screen it can start below the fold. It must still be scrollable to.
      final scrollable = find.byType(Scrollable);
      expect(scrollable, findsWidgets);

      await tester.scrollUntilVisible(
        find.text('Confirm Location'),
        120,
        scrollable: scrollable.first,
      );
      expect(find.text('Confirm Location'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the saved address is not cut off vertically', () {
    // The reported bug: the address in the dialog read as a single sliced-off
    // line. The field was a `DropdownButtonFormField`, whose collapsed button
    // hands the address a tight 24px — exactly one line at this font — no matter
    // how many lines the address actually needs. Anything wrapping to two lines
    // had its lower half chopped off, so the customer could not read the
    // address they were about to confirm.
    //
    // This measures the rendered paragraph against the height the text actually
    // asked for, which is what "clipped" means in layout terms.

    const wrappingAddress =
        'Trinl one hotel near comsats, Mansehra Road, Abbottabad';

    Future<void> pumpAddress(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(720, 1600)
        ..devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      deviceSource = FakeDeviceLocationSource(
        permission: LocationPermissionOutcome.granted,
        fix: fix,
      );

      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('user-1'),
          addressesFutureProvider.overrideWith(
            (ref) async => const [
              UserAddress(
                id: 'addr-1',
                userId: 'user-1',
                label: 'Home',
                addressLine: wrappingAddress,
                isDefault: true,
              ),
            ],
          ),
          locationRepositoryProvider.overrideWithValue(
            LocationRepository(
              deviceSource: deviceSource,
              addressLookup: FakeAddressTextLookup(result: 'Abbottabad'),
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
    }

    /// The height the text needs to draw every line, versus what it was given.
    ///
    /// The painter is laid out with the same max lines and the same width the
    /// real paragraph received, so the two heights are directly comparable: when
    /// the widget is clipped the paragraph is shorter than the painter needs.
    void expectFullyVisible(Finder finder) {
      final element = finder.evaluate().first;
      final paragraph = element.renderObject! as RenderParagraph;
      final widget = element.widget as Text;
      final style = DefaultTextStyle.of(element).style.merge(widget.style);

      final painter = TextPainter(
        text: TextSpan(text: wrappingAddress, style: style),
        textDirection: TextDirection.ltr,
        maxLines: widget.maxLines,
        strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
      )..layout(maxWidth: paragraph.constraints.maxWidth);

      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(painter.height),
        reason: 'the address needs ${painter.height}px to draw all '
            '${painter.computeLineMetrics().length} lines but was only given '
            '${paragraph.size.height}px, so the bottom of the text is being '
            'sliced off',
      );
    }

    testWidgets('the preselected address in the field is not sliced',
        (tester) async {
      await pumpAddress(tester);

      expect(find.text(wrappingAddress), findsOneWidget);
      expectFullyVisible(find.text(wrappingAddress));
      expect(tester.takeException(), isNull);
    });

    testWidgets('every address in the list is not sliced', (tester) async {
      await pumpAddress(tester);

      await tester.tap(find.byKey(const Key(SavedAddressPickerField.fieldKey)));
      await tester.pumpAndSettle();

      // Two: the field behind the sheet still shows the same address, and the
      // sheet's row is the one on top.
      expect(find.text(wrappingAddress), findsNWidgets(2));
      expectFullyVisible(find.text(wrappingAddress).last);
      expect(tester.takeException(), isNull);
    });

    testWidgets('still works at a large text scale', (tester) async {
      tester.view
        ..physicalSize = const Size(720, 1600)
        ..devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue('user-1'),
          addressesFutureProvider.overrideWith(
            (ref) async => const [
              UserAddress(
                id: 'addr-1',
                userId: 'user-1',
                label: 'Home',
                addressLine: wrappingAddress,
                isDefault: true,
              ),
            ],
          ),
          locationRepositoryProvider.overrideWithValue(
            LocationRepository(
              deviceSource: FakeDeviceLocationSource(
                permission: LocationPermissionOutcome.granted,
                fix: fix,
              ),
              addressLookup: FakeAddressTextLookup(result: 'Abbottabad'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const LocationSelectionDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expectFullyVisible(find.text(wrappingAddress));
      expect(tester.takeException(), isNull);
    });
  });

  group('confirming does not require picking anything first', () {
    // The regression this whole group is about. The dialog opened with nothing
    // selected and `_select` returned early when both the text field and the
    // dropdown were empty — so "Confirm Location" was a dead button and the only
    // way through was opening the dropdown and choosing something on every
    // visit, including the ones where the customer had already marked a default.
    UserAddress home(
        {required String id, required String line, bool isDefault = false}) {
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
