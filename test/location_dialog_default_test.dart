import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/profile/models/profile.dart';
import 'package:mrpizza/widgets/shared_components.dart';

/// The location dialog used to open with nothing selected. "Confirm Location"
/// then returned early doing nothing at all, because both the text field and the
/// dropdown were empty — so the customer's only way forward was to open the
/// dropdown and choose an address on every single visit, including the ones
/// where they had already told the app which address they use.
///
/// These cover the rule that removes that tap: the address the customer marked
/// as their default is what the dialog opens with.
UserAddress address({
  required String id,
  required String line,
  bool isDefault = false,
}) {
  return UserAddress(
    id: id,
    userId: 'customer-1',
    label: 'Home',
    addressLine: line,
    isDefault: isDefault,
  );
}

void main() {
  group('the dialog opens on the default address', () {
    test('the marked default is chosen', () {
      final visible = [
        address(id: '1', line: 'Office, Blue Area'),
        address(id: '2', line: 'House 12, Mandian', isDefault: true),
      ];

      expect(defaultSavedAddress(visible)?.id, '2');
    });

    test('the first on file is used when none is marked default', () {
      // Better than opening empty. A customer with saved addresses who never
      // marked one still gets a working Confirm on the first tap.
      final visible = [
        address(id: '1', line: 'House 12, Mandian'),
        address(id: '2', line: 'Office, Blue Area'),
      ];

      expect(defaultSavedAddress(visible)?.id, '1');
    });

    test('no saved addresses means nothing to preselect', () {
      expect(defaultSavedAddress(const []), isNull);
    });
  });

  group('the address already in use is left out of the choices', () {
    test('the current address is not offered as a choice', () {
      final visible = savedAddressesForDialog(
        addresses: [
          address(id: '1', line: 'House 12, Mandian'),
          address(id: '2', line: 'Office, Blue Area'),
        ],
        currentAddressText: 'House 12, Mandian',
      );

      expect(visible.map((a) => a.id), ['2']);
    });

    test('duplicate rows for one address appear once', () {
      // Duplicate address rows are possible and would otherwise show up twice in
      // the dropdown with no way to tell them apart.
      final visible = savedAddressesForDialog(
        addresses: [
          address(id: '1', line: 'House 12, Mandian', isDefault: true),
          address(id: '1', line: 'House 12, Mandian'),
          address(id: '2', line: 'Office, Blue Area'),
        ],
        currentAddressText: null,
      );

      expect(visible.map((a) => a.id), ['1', '2']);
    });

    test('the chosen address is always one the dialog can actually show', () {
      // The failure this guards: preselecting an address that is filtered out of
      // the visible list would leave state believing something was selected while
      // the field still showed its placeholder — the customer would see an
      // untouched dropdown and assume the fix had not worked.
      final addresses = [
        address(id: '1', line: 'House 12, Mandian', isDefault: true),
        address(id: '2', line: 'Office, Blue Area'),
      ];
      final visible = savedAddressesForDialog(
        addresses: addresses,
        currentAddressText: 'House 12, Mandian',
      );

      final chosen = defaultSavedAddress(visible);

      expect(chosen, isNotNull);
      expect(visible.any((a) => a == chosen), isTrue);
    });

    test('a default that is already the current address falls through cleanly', () {
      // The default is excluded because it is already applied. The dialog still
      // has to preselect something the customer can see, rather than nothing.
      final visible = savedAddressesForDialog(
        addresses: [
          address(id: '1', line: 'House 12, Mandian', isDefault: true),
          address(id: '2', line: 'Office, Blue Area'),
        ],
        currentAddressText: 'House 12, Mandian',
      );

      expect(defaultSavedAddress(visible)?.id, '2');
    });
  });
}