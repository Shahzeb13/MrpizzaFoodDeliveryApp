import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/orders/models/branch.dart';
import 'package:mrpizza/features/orders/providers/orders_provider.dart';
import 'package:mrpizza/features/profile/models/profile.dart';

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

  const addressNearAbbottabad = UserAddress(
    id: 'addr-1',
    userId: 'user-1',
    label: 'Home',
    addressLine: 'Al Mansoor Town, Abbottabad',
    latitude: 34.2045,
    longitude: 73.2400,
  );

  const addressNearMansehra = UserAddress(
    id: 'addr-2',
    userId: 'user-1',
    label: 'Work',
    addressLine: 'Mansehra city',
    latitude: 34.3290,
    longitude: 73.1980,
  );

  const addressWithoutCoordinates = UserAddress(
    id: 'addr-3',
    userId: 'user-1',
    label: 'Unpinned',
    addressLine: 'Somewhere in Khyber Pakhtunkhwa',
  );

  group('BranchSelection.selectNearestBranch', () {
    test('picks the closer branch when the address has coordinates', () {
      final selection = BranchSelection.selectNearestBranch(
        addressNearAbbottabad,
        [abbottabad, mansehra],
      );

      expect(selection.branch?.id, 'branch-abbottabad');
      expect(selection.isNearestToAddress, isTrue);
    });

    test('picks the other branch when the address is closer to it', () {
      final selection = BranchSelection.selectNearestBranch(
        addressNearMansehra,
        [abbottabad, mansehra],
      );

      expect(selection.branch?.id, 'branch-mansehra');
      expect(selection.isNearestToAddress, isTrue);
    });

    test('claims no nearest branch when the address has no coordinates', () {
      final selection = BranchSelection.selectNearestBranch(
        addressWithoutCoordinates,
        [abbottabad, mansehra],
      );

      expect(selection.branch, isNull);
      expect(selection.isNearestToAddress, isFalse);
    });

    test('claims no nearest branch when no branch has coordinates', () {
      const uncoordinatedBranch = Branch(id: 'branch-x', name: 'No Coords');

      final selection = BranchSelection.selectNearestBranch(
        addressNearAbbottabad,
        [uncoordinatedBranch],
      );

      expect(selection.branch?.id, 'branch-x');
      expect(selection.isNearestToAddress, isFalse);
    });

    test('returns no branch when there are no branches at all', () {
      final selection = BranchSelection.selectNearestBranch(
        addressNearAbbottabad,
        const <Branch>[],
      );

      expect(selection.branch, isNull);
      expect(selection.isNearestToAddress, isFalse);
    });
  });

  group('CheckoutNotifier.selectAddress', () {
    test('records that the branch really is the nearest one', () {
      final notifier = CheckoutNotifier();

      notifier.selectAddress(
        addressNearAbbottabad,
        branches: [abbottabad, mansehra],
      );

      expect(notifier.state.branch?.id, 'branch-abbottabad');
      expect(notifier.state.branchIsNearest, isTrue);
    });

    test('does not claim nearest when the address has no coordinates', () {
      final notifier = CheckoutNotifier();

      notifier.selectAddress(
        addressWithoutCoordinates,
        branches: [abbottabad, mansehra],
      );

      expect(notifier.state.branch, isNull);
      expect(notifier.state.branchIsNearest, isFalse);
    });
  });

  group('CheckoutNotifier.selectDeliveryDefault', () {
    test('falls back to the default address and reports no nearest branch', () {
      final notifier = CheckoutNotifier();

      notifier.selectDeliveryDefault(
        addresses: [addressWithoutCoordinates],
        branches: [abbottabad, mansehra],
      );

      expect(notifier.state.address?.id, 'addr-3');
      expect(notifier.state.branch, isNull);
      expect(notifier.state.branchIsNearest, isFalse);
    });

    test('picks a branch but claims no nearest when there are no addresses', () {
      final notifier = CheckoutNotifier();

      notifier.selectDeliveryDefault(
        addresses: const <UserAddress>[],
        branches: [abbottabad, mansehra],
      );

      expect(notifier.state.branch?.id, 'branch-abbottabad');
      expect(notifier.state.branchIsNearest, isFalse);
    });

    test('selects the nearest branch for a pinned default address', () {
      const pinnedDefault = UserAddress(
        id: 'addr-4',
        userId: 'user-1',
        label: 'Home',
        addressLine: 'Mansehra city',
        latitude: 34.3290,
        longitude: 73.1980,
        isDefault: true,
      );
      final notifier = CheckoutNotifier();

      notifier.selectDeliveryDefault(
        addresses: [addressWithoutCoordinates, pinnedDefault],
        branches: [abbottabad, mansehra],
      );

      expect(notifier.state.address?.id, 'addr-4');
      expect(notifier.state.branch?.id, 'branch-mansehra');
      expect(notifier.state.branchIsNearest, isTrue);
    });
  });

  test('checkoutProvider starts with no branch and no nearest claim', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final state = container.read(checkoutProvider);

    expect(state.branch, isNull);
    expect(state.branchIsNearest, isFalse);
  });
}
