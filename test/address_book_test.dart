import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/profile/data/address_book.dart';
import 'package:mrpizza/features/profile/models/profile.dart';

/// Selecting a location at startup used to update only the in-memory pin, so
/// nothing ever reached the `addresses` table and My Addresses stayed empty.
void main() {
  const home = UserAddress(
    id: 'addr-home',
    userId: 'user-1',
    label: 'Home',
    addressLine: 'Al Mansoor Town, Abbottabad',
    latitude: 34.2045,
    longitude: 73.2400,
    isDefault: true,
  );

  const unpinned = UserAddress(
    id: 'addr-old',
    userId: 'user-1',
    label: 'Old',
    addressLine: 'near comsats',
  );

  group('deriveLabel', () {
    test('uses the opening words of the address text', () {
      expect(
        AddressBook.deriveLabel('Triple one hotel near comsats'),
        'Triple one',
      );
    });

    test('keeps the first two comma segments', () {
      expect(
        AddressBook.deriveLabel('House 12, Street 4, Abbottabad'),
        'House 12, Street 4',
      );
    });

    test('drops the city tail so the label stays short', () {
      expect(
        AddressBook.deriveLabel('Al Mansoor Town, Abbottabad'),
        'Al Mansoor Town',
      );
    });

    test('falls back when there is no text to work with', () {
      expect(AddressBook.deriveLabel(''), 'Current Location');
      expect(AddressBook.deriveLabel('   '), 'Current Location');
    });

    test('never returns an empty label', () {
      expect(AddressBook.deriveLabel(',,, ,'), isNotEmpty);
    });

    test('caps a very long address so the label stays readable', () {
      final label = AddressBook.deriveLabel(
        'Some Extremely Long Street Name That Goes On And On Forever Avenue',
      );

      expect(label.length, lessThanOrEqualTo(AddressBook.maximumLabelLength));
    });
  });

  group('findExistingAtPoint', () {
    test('reuses a saved address at the same spot', () {
      final match = AddressBook.findExistingAtPoint(
        saved: const [home],
        latitude: 34.2045,
        longitude: 73.2400,
      );

      expect(match?.id, 'addr-home');
    });

    test('reuses a saved address just around the corner', () {
      // ~20 metres north of Home.
      final match = AddressBook.findExistingAtPoint(
        saved: const [home],
        latitude: 34.20468,
        longitude: 73.2400,
      );

      expect(match?.id, 'addr-home');
    });

    test('creates a new address when the point is genuinely elsewhere', () {
      final match = AddressBook.findExistingAtPoint(
        saved: const [home],
        latitude: 34.3290,
        longitude: 73.1980,
      );

      expect(match, isNull);
    });

    test('matches nothing when the address has no coordinates', () {
      final match = AddressBook.findExistingAtPoint(
        saved: const [unpinned],
        latitude: 34.2045,
        longitude: 73.2400,
      );

      expect(match, isNull);
    });

    test('matches nothing when nothing is saved yet', () {
      final match = AddressBook.findExistingAtPoint(
        saved: const [],
        latitude: 34.2045,
        longitude: 73.2400,
      );

      expect(match, isNull);
    });

    test('picks the closest of several saved addresses', () {
      const mansehra = UserAddress(
        id: 'addr-mansehra',
        userId: 'user-1',
        label: 'Work',
        addressLine: 'Mansehra city',
        latitude: 34.3290,
        longitude: 73.1980,
      );

      final match = AddressBook.findExistingAtPoint(
        saved: const [home, mansehra],
        latitude: 34.32895,
        longitude: 73.1981,
      );

      expect(match?.id, 'addr-mansehra');
    });
  });

  group('findExistingByText', () {
    test('reuses an address with the same text, ignoring case and spacing', () {
      final match = AddressBook.findExistingByText(
        saved: const [unpinned],
        addressLine: '  Near   COMSATS ',
      );

      expect(match?.id, 'addr-old');
    });

    test('does not match a different address', () {
      final match = AddressBook.findExistingByText(
        saved: const [unpinned],
        addressLine: 'Somewhere else entirely',
      );

      expect(match, isNull);
    });

    test('does not match on an empty query', () {
      final match = AddressBook.findExistingByText(
        saved: const [unpinned],
        addressLine: '   ',
      );

      expect(match, isNull);
    });
  });

  group('classifyLocationSelection', () {
    test('reuses the nearby address instead of creating a duplicate', () {
      final outcome = AddressBook.classifyLocationSelection(
        saved: const [home],
        addressLine: 'Al Mansoor Town, Abbottabad',
        latitude: 34.2045,
        longitude: 73.2400,
      );

      expect(outcome.existing?.id, 'addr-home');
      expect(outcome.shouldInsert, isFalse);
    });

    test('creates a new address for a point that is not saved yet', () {
      final outcome = AddressBook.classifyLocationSelection(
        saved: const [home],
        addressLine: 'Mansehra city',
        latitude: 34.3290,
        longitude: 73.1980,
      );

      expect(outcome.shouldInsert, isTrue);
      expect(outcome.label, 'Mansehra city');
    });

    test('reuses by text when there are no coordinates to compare', () {
      final outcome = AddressBook.classifyLocationSelection(
        saved: const [unpinned],
        addressLine: 'near comsats',
        latitude: null,
        longitude: null,
      );

      expect(outcome.existing?.id, 'addr-old');
      expect(outcome.shouldInsert, isFalse);
    });

    test('inserts a typed address with no coordinates and no match', () {
      final outcome = AddressBook.classifyLocationSelection(
        saved: const [unpinned],
        addressLine: 'a brand new place',
        latitude: null,
        longitude: null,
      );

      expect(outcome.shouldInsert, isTrue);
    });

    test('the first ever address is flagged to become the default', () {
      final outcome = AddressBook.classifyLocationSelection(
        saved: const [],
        addressLine: 'First ever address',
        latitude: 34.2,
        longitude: 73.2,
      );

      expect(outcome.shouldInsert, isTrue);
      expect(outcome.shouldBecomeDefault, isTrue);
    });

    test('a later address does not steal the default flag', () {
      final outcome = AddressBook.classifyLocationSelection(
        saved: const [home],
        addressLine: 'Somewhere new',
        latitude: 34.3290,
        longitude: 73.1980,
      );

      expect(outcome.shouldInsert, isTrue);
      expect(outcome.shouldBecomeDefault, isFalse);
    });
  });

  group('nearestBranchFor', () {
    test('is not part of the address book; addresses carry no branch logic', () {
      expect(AddressBook.duplicateRadiusMetres, greaterThan(0));
    });
  });
}
