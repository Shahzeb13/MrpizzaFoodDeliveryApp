import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/location_provider.dart';
import 'package:mrpizza/features/location/data/location_repository.dart';
import 'package:mrpizza/features/location/models/captured_location.dart';
import 'package:mrpizza/features/orders/models/branch.dart';
import 'package:mrpizza/features/orders/providers/orders_provider.dart';
import 'package:mrpizza/features/profile/models/profile.dart';

import 'support/fake_location_sources.dart';

/// Covers the gap that blocked checkout: a location captured on the home
/// screen never reached the checkout branch, so Confirm Order dead-ended with
/// "Please select a branch first."
void main() {
  const abbottabad = Branch(
    id: 'branch-abbottabad',
    name: 'Abbottabad',
    latitude: 34.204008,
    longitude: 73.238723,
  );
  const mansehra = Branch(
    id: 'branch-mansehra',
    name: 'Mansehra',
    latitude: 34.328686,
    longitude: 73.199313,
  );
  const allBranches = [abbottabad, mansehra];

  const unpinnedDefaultAddress = UserAddress(
    id: 'addr-unpinned',
    userId: 'user-1',
    label: 'Home',
    addressLine: 'near comsats',
    isDefault: true,
  );

  group('BranchSelection.selectNearestBranchToPoint', () {
    test('picks the closer branch for a point near Abbottabad', () {
      final selection = BranchSelection.selectNearestBranchToPoint(
        latitude: 34.2045,
        longitude: 73.24,
        branches: allBranches,
      );

      expect(selection.branch?.id, 'branch-abbottabad');
      expect(selection.isNearestToAddress, isTrue);
    });

    test('picks the closer branch for a point near Mansehra', () {
      final selection = BranchSelection.selectNearestBranchToPoint(
        latitude: 34.3290,
        longitude: 73.1980,
        branches: allBranches,
      );

      expect(selection.branch?.id, 'branch-mansehra');
      expect(selection.isNearestToAddress, isTrue);
    });

    test('claims no branch when the point has no longitude', () {
      final selection = BranchSelection.selectNearestBranchToPoint(
        latitude: 34.2045,
        longitude: null,
        branches: allBranches,
      );

      expect(selection.branch, isNull);
      expect(selection.isNearestToAddress, isFalse);
    });

    test('claims no branch when there are no branches', () {
      final selection = BranchSelection.selectNearestBranchToPoint(
        latitude: 34.2045,
        longitude: 73.24,
        branches: const <Branch>[],
      );

      expect(selection.branch, isNull);
    });
  });

  group('CheckoutNotifier.syncBranchFromPin', () {
    test('resolves the nearest branch from the live map pin', () {
      final notifier = CheckoutNotifier();

      notifier.syncBranchFromPin(
        latitude: 34.3290,
        longitude: 73.1980,
        branches: allBranches,
      );

      expect(notifier.state.branch?.id, 'branch-mansehra');
      expect(notifier.state.branchIsNearest, isTrue);
    });

    test('resolves a branch even when no saved address is chosen yet', () {
      final notifier = CheckoutNotifier();

      notifier.syncBranchFromPin(
        latitude: 34.2045,
        longitude: 73.24,
        branches: allBranches,
      );

      expect(notifier.state.branch?.id, 'branch-abbottabad');
      expect(notifier.state.branchIsNearest, isTrue);
      expect(notifier.state.address, isNull);
    });

    test('leaves a hand-picked branch alone', () {
      final notifier = CheckoutNotifier();
      notifier.selectBranch(mansehra);

      notifier.syncBranchFromPin(
        latitude: 34.2045,
        longitude: 73.24,
        branches: allBranches,
      );

      expect(notifier.state.branch?.id, 'branch-mansehra');
      expect(notifier.state.branchIsNearest, isFalse);
    });

    test('keeps an already-resolved branch when the pin is absent', () {
      final notifier = CheckoutNotifier();
      notifier.syncBranchFromPin(
        latitude: 34.2045,
        longitude: 73.24,
        branches: allBranches,
      );

      notifier.syncBranchFromPin(
        latitude: null,
        longitude: null,
        branches: allBranches,
      );

      expect(notifier.state.branch?.id, 'branch-abbottabad');
      expect(notifier.state.branchIsNearest, isTrue);
    });

    test('moves the branch when the customer relocates the pin', () {
      final notifier = CheckoutNotifier();
      notifier.syncBranchFromPin(
        latitude: 34.2045,
        longitude: 73.24,
        branches: allBranches,
      );

      notifier.syncBranchFromPin(
        latitude: 34.3290,
        longitude: 73.1980,
        branches: allBranches,
      );

      expect(notifier.state.branch?.id, 'branch-mansehra');
    });

    test('never claims nearest when the branches have no coordinates', () {
      final notifier = CheckoutNotifier();

      notifier.syncBranchFromPin(
        latitude: 34.2045,
        longitude: 73.24,
        branches: const [Branch(id: 'branch-x', name: 'No Coords')],
      );

      expect(notifier.state.branchIsNearest, isFalse);
    });
  });

  group('a hand-picked branch outranks an automatic one', () {
    test('remembers that the customer chose the branch by hand', () {
      final notifier = CheckoutNotifier();

      notifier.selectBranch(mansehra);

      expect(notifier.state.branchWasChosenManually, isTrue);
    });

    test('an automatic branch is not marked as hand-picked', () {
      final notifier = CheckoutNotifier();

      notifier.syncBranchFromPin(
        latitude: 34.2045,
        longitude: 73.24,
        branches: allBranches,
      );

      expect(notifier.state.branchWasChosenManually, isFalse);
    });

    test('choosing by hand again still wins after an automatic pick', () {
      final notifier = CheckoutNotifier();
      notifier.syncBranchFromPin(
        latitude: 34.2045,
        longitude: 73.24,
        branches: allBranches,
      );

      notifier.selectBranch(mansehra);
      notifier.syncBranchFromPin(
        latitude: 34.2045,
        longitude: 73.24,
        branches: allBranches,
      );

      expect(notifier.state.branch?.id, 'branch-mansehra');
    });
  });

  group('selectDeliveryDefault must not undo a resolved branch', () {
    test('keeps the branch when the default address has no coordinates', () {
      final notifier = CheckoutNotifier();
      notifier.syncBranchFromPin(
        latitude: 34.2045,
        longitude: 73.24,
        branches: allBranches,
      );

      notifier.selectDeliveryDefault(
        addresses: [unpinnedDefaultAddress],
        branches: allBranches,
      );

      expect(notifier.state.address?.id, 'addr-unpinned');
      expect(notifier.state.branch?.id, 'branch-abbottabad');
    });

    test('re-resolves the branch when the default address has coordinates', () {
      final notifier = CheckoutNotifier();
      notifier.syncBranchFromPin(
        latitude: 34.2045,
        longitude: 73.24,
        branches: allBranches,
      );

      notifier.selectDeliveryDefault(
        addresses: const [
          UserAddress(
            id: 'addr-pinned',
            userId: 'user-1',
            label: 'Work',
            addressLine: 'Mansehra city',
            latitude: 34.3290,
            longitude: 73.1980,
            isDefault: true,
          ),
        ],
        branches: allBranches,
      );

      expect(notifier.state.branch?.id, 'branch-mansehra');
    });
  });

  group('the pin captured on the home screen reaches checkout', () {
    test('a GPS fix resolves the checkout branch', () async {
      final container = ProviderContainer(
        overrides: [
          locationRepositoryProvider.overrideWithValue(
            LocationRepository(
              deviceSource: FakeDeviceLocationSource(
                fix: const CapturedCoordinates(
                  latitude: 34.2045,
                  longitude: 73.24,
                ),
              ),
              addressLookup: FakeAddressTextLookup(
                result: 'Al Mansoor Town, Abbottabad',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final location = container.read(locationProvider);
      expect(location.hasCoordinates, isFalse);

      // Home screen: customer taps "use my location".
      await container.read(locationProvider.notifier).useCurrentLocation();
      final captured = container.read(locationProvider);
      expect(captured.hasCoordinates, isTrue);

      // Checkout: the pin is pushed into the branch selection.
      container.read(checkoutProvider.notifier).syncBranchFromPin(
            latitude: captured.latitude,
            longitude: captured.longitude,
            branches: allBranches,
          );

      final checkout = container.read(checkoutProvider);
      expect(checkout.branch?.id, 'branch-abbottabad');
      expect(checkout.branchIsNearest, isTrue);
    });
  });

  group('LocationNotifier.setLocation geocodes the typed text', () {
    (LocationNotifier, FakeForwardGeocoder) buildNotifier({
      CapturedCoordinates? geocoded,
      Object? geocodeError,
    }) {
      final forwardGeocoder = FakeForwardGeocoder(
        coordinates: geocoded,
        error: geocodeError,
      );
      return (
        LocationNotifier(
          repository: LocationRepository(
            deviceSource: FakeDeviceLocationSource(),
            addressLookup: FakeAddressTextLookup(result: 'unused'),
            coordinateLookup: forwardGeocoder,
          ),
        ),
        forwardGeocoder,
      );
    }

    test('fills in coordinates so a branch can be calculated', () async {
      final (notifier, _) = buildNotifier(
        geocoded: const CapturedCoordinates(
          latitude: 34.3290,
          longitude: 73.1980,
        ),
      );

      await notifier.setLocation('Mansehra city');

      expect(notifier.state.address, 'Mansehra city');
      expect(notifier.state.latitude, 34.3290);
      expect(notifier.state.longitude, 73.1980);
    });

    test('keeps the typed text when nothing matches', () async {
      final (notifier, _) = buildNotifier();

      await notifier.setLocation('near comsats');

      expect(notifier.state.address, 'near comsats');
      expect(notifier.state.isSet, isTrue);
      expect(notifier.state.latitude, isNull);
      expect(notifier.state.errorMessage, isNull);
    });

    test('keeps the typed text when geocoding blows up', () async {
      final (notifier, _) = buildNotifier(geocodeError: Exception('offline'));

      await notifier.setLocation('near comsats');

      expect(notifier.state.address, 'near comsats');
      expect(notifier.state.latitude, isNull);
      expect(notifier.state.errorMessage, isNull);
    });

    test('reports progress while the text is being geocoded', () async {
      final (notifier, _) = buildNotifier(
        geocoded: const CapturedCoordinates(
          latitude: 34.3290,
          longitude: 73.1980,
        ),
      );

      final pending = notifier.setLocation('Mansehra city');
      expect(notifier.state.isCapturing, isTrue);
      expect(notifier.state.address, 'Mansehra city');

      await pending;
      expect(notifier.state.isCapturing, isFalse);
    });
  });
}
