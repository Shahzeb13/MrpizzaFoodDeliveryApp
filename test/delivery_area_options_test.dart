import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/location/data/delivery_area_options.dart';
import 'package:mrpizza/features/location/models/captured_location.dart';
import 'package:mrpizza/features/orders/models/branch.dart';
import 'package:mrpizza/features/profile/models/profile.dart';

void main() {
  group('cityFromBranchName', () {
    test('takes the city after an en dash', () {
      expect(cityFromBranchName('Mr. Pizza – Abbottabad'), 'Abbottabad');
    });

    test('takes the city after a plain hyphen', () {
      expect(cityFromBranchName('Mr. Pizza - Mansehra'), 'Mansehra');
    });

    test('uses a name with no separator whole rather than guessing', () {
      expect(cityFromBranchName('Mansehra'), 'Mansehra');
    });

    test('is empty for a blank name', () {
      expect(cityFromBranchName('   '), isNull);
      expect(cityFromBranchName(null), isNull);
    });
  });

  group('deliveryCitiesFromBranches', () {
    test('lists the real branch cities alphabetically', () {
      final cities = deliveryCitiesFromBranches(const [
        Branch(id: 'b2', name: 'Mr. Pizza – Mansehra'),
        Branch(id: 'b1', name: 'Mr. Pizza – Abbottabad'),
      ]);

      expect(cities.map((c) => c.name), ['Abbottabad', 'Mansehra']);
    });

    test('keeps the branch so the map can be centred on it', () {
      const branches = [
        Branch(
          id: 'b1',
          name: 'Mr. Pizza – Abbottabad',
          latitude: 34.1688,
          longitude: 73.2215,
        ),
      ];

      final cities = deliveryCitiesFromBranches(branches);

      expect(cities.single.branch?.latitude, 34.1688);
    });

    test('offers nothing for an empty catalog rather than inventing a city',
        () {
      expect(deliveryCitiesFromBranches(const []), isEmpty);
    });

    test('does not repeat a city that has two branches', () {
      final cities = deliveryCitiesFromBranches(const [
        Branch(id: 'b1', name: 'Mr. Pizza – Abbottabad'),
        Branch(id: 'b2', name: 'Mr. Pizza - Abbottabad'),
      ]);

      expect(cities.length, 1);
    });
  });

  group('searchSavedAddresses', () {
    const saved = [
      UserAddress(
        id: 'a1',
        userId: 'u1',
        label: 'Home',
        addressLine: 'House 12, Street 4, Abbottabad',
      ),
      UserAddress(
        id: 'a2',
        userId: 'u1',
        label: 'Office',
        addressLine: 'University Road, Mansehra',
      ),
    ];

    test('an empty query returns every place', () {
      expect(searchSavedAddresses(saved: saved), hasLength(2));
      expect(searchSavedAddresses(saved: saved, query: '   '), hasLength(2));
    });

    test('matches the address line, ignoring case', () {
      final found = searchSavedAddresses(saved: saved, query: 'mansehra');
      expect(found.map((a) => a.id), ['a2']);
    });

    test('matches the short label', () {
      final found = searchSavedAddresses(saved: saved, query: 'home');
      expect(found.map((a) => a.id), ['a1']);
    });

    test('a query nothing matches returns an empty list, not everything', () {
      expect(searchSavedAddresses(saved: saved, query: 'islamabad'), isEmpty);
    });
  });

  group('composeMapPickAddress', () {
    test('joins the chosen area and city', () {
      expect(
        composeMapPickAddress(city: 'Abbottabad', areaOrLandmark: 'Block C'),
        'Block C, Abbottabad',
      );
    });

    test('uses the city alone when no landmark was typed', () {
      expect(
        composeMapPickAddress(city: 'Mansehra'),
        'Mansehra',
      );
    });

    test('uses the landmark alone when no city was chosen', () {
      expect(
        composeMapPickAddress(areaOrLandmark: 'Near the main gate'),
        'Near the main gate',
      );
    });

    test('falls back to the reverse-geocoded line only when nothing was typed',
        () {
      expect(
        composeMapPickAddress(
          reverseGeocoded: 'Cannon Road, Abbottabad, Pakistan',
        ),
        'Cannon Road, Abbottabad, Pakistan',
      );
    });

    test('a typed landmark wins over the reverse-geocoded line', () {
      expect(
        composeMapPickAddress(
          city: 'Abbottabad',
          areaOrLandmark: 'Blue area',
          reverseGeocoded: 'Cannon Road, Abbottabad',
        ),
        'Blue area, Abbottabad',
      );
    });

    test('is empty when the customer chose nothing at all', () {
      expect(composeMapPickAddress(city: null, areaOrLandmark: '  '), '');
    });
  });

  group('canConfirmMapPick', () {
    test('allows a real point with something to call it', () {
      expect(
        canConfirmMapPick(
          latitude: 34.1688,
          longitude: 73.2215,
          hasUsableAddressText: true,
        ),
        isTrue,
      );
    });

    test('refuses while the map has produced no point', () {
      expect(
        canConfirmMapPick(
          latitude: null,
          longitude: null,
          hasUsableAddressText: true,
        ),
        isFalse,
      );
    });

    test('refuses a point with nothing to call it', () {
      expect(
        canConfirmMapPick(
          latitude: 34.1688,
          longitude: 73.2215,
          hasUsableAddressText: false,
        ),
        isFalse,
      );
    });

    test('refuses the 0,0 "no fix" reading a map can report', () {
      expect(
        canConfirmMapPick(
          latitude: 0,
          longitude: 0,
          hasUsableAddressText: true,
        ),
        isFalse,
      );
    });

    test('refuses out-of-range and NaN readings', () {
      expect(
        canConfirmMapPick(
          latitude: 91,
          longitude: 73,
          hasUsableAddressText: true,
        ),
        isFalse,
      );
      expect(
        canConfirmMapPick(
          latitude: double.nan,
          longitude: 73,
          hasUsableAddressText: true,
        ),
        isFalse,
      );
    });
  });

  group('formatPickedCoordinates', () {
    test('shows five decimals, about a metre', () {
      expect(
        formatPickedCoordinates(latitude: 34.168812, longitude: 73.221534),
        '34.16881, 73.22153',
      );
    });

    test('says so plainly when there is no point', () {
      expect(
        formatPickedCoordinates(latitude: null, longitude: null),
        'Coordinates unavailable',
      );
    });
  });

  group('CapturedCoordinates.isPlausibleEarth', () {
    test('accepts a point in the delivery cities', () {
      expect(CapturedCoordinates.isPlausibleEarth(34.1688, 73.2215), isTrue);
      expect(CapturedCoordinates.isPlausibleEarth(34.3302, 73.1969), isTrue);
    });

    test('rejects 0,0, out-of-range, and NaN', () {
      expect(CapturedCoordinates.isPlausibleEarth(0, 0), isFalse);
      expect(CapturedCoordinates.isPlausibleEarth(-91, 73), isFalse);
      expect(CapturedCoordinates.isPlausibleEarth(34, 181), isFalse);
      expect(CapturedCoordinates.isPlausibleEarth(double.nan, 73), isFalse);
    });
  });
}
