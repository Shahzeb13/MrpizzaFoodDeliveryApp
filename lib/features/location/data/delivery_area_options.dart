import '../../orders/models/branch.dart';
import '../../profile/models/profile.dart';
import '../models/captured_location.dart';

/// A city the app can actually deliver to.
///
/// Taken from the `branches` table rather than a hardcoded list, so a branch
/// that is renamed, added, or removed changes what the picker offers without a
/// code change — and no locality is ever offered that the app does not serve.
class DeliveryCity {
  /// The city name shown to the customer, e.g. "Abbottabad".
  final String name;

  /// The branch this city was derived from, when there is one.
  final Branch? branch;

  const DeliveryCity({required this.name, this.branch});

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DeliveryCity && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// Pulls the city out of a branch name.
///
/// Branch rows are named things like "Mr. Pizza – Abbottabad" (en dash) or
/// "Mr. Pizza - Mansehra" (hyphen), so the city is whatever follows the last
/// separator. A name with no separator is used whole rather than guessed at,
/// which keeps the label honest instead of inventing a locality.
///
/// Returns null only for a blank name, which cannot happen for a real row.
String? cityFromBranchName(String? branchName) {
  final trimmed = (branchName ?? '').trim();
  if (trimmed.isEmpty) return null;

  for (final separator in const ['–', '—', '-', '|', ',']) {
    final index = trimmed.lastIndexOf(separator);
    if (index < 0) continue;
    final tail = trimmed.substring(index + separator.length).trim();
    if (tail.isNotEmpty) return tail;
  }
  return trimmed;
}

/// The distinct delivery cities behind [branches], alphabetically.
///
/// No eligibility rule is applied here. This only says which cities the
/// restaurant has a branch in; whether a particular address is deliverable is
/// the branch's decision, not the picker's.
List<DeliveryCity> deliveryCitiesFromBranches(List<Branch> branches) {
  final byName = <String, DeliveryCity>{};

  for (final branch in branches) {
    final city = cityFromBranchName(branch.name);
    if (city == null) continue;
    // First branch wins for a repeated city, so the coordinates come from a
    // single stable row rather than whichever branch happened to sort last.
    byName.putIfAbsent(city, () => DeliveryCity(name: city, branch: branch));
  }

  final cities = byName.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return cities;
}

/// Filters the customer's own saved places by a free-text query.
///
/// An empty query returns [saved] unchanged so the customer is not told their
/// list is empty just because they have not typed yet. Matching is
/// case-insensitive and covers both the short label and the full address line.
List<UserAddress> searchSavedAddresses({
  required List<UserAddress> saved,
  String query = '',
}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return List.of(saved);

  return saved
      .where(
        (address) =>
            address.addressLine.toLowerCase().contains(needle) ||
            address.label.toLowerCase().contains(needle),
      )
      .toList();
}

/// The address line stored for a map pick.
///
/// Deliberately built from what the customer actually chose: the area or
/// landmark they typed or picked, then the city they selected. GPS coordinates
/// are saved alongside it, but coordinates are not a street address and are
/// never dressed up as one here.
///
/// A reverse-geocoded line (from the GPS button) is used when the customer has
/// not described the place themselves, so the common one-tap case still reads
/// like an address.
String composeMapPickAddress({
  String? city,
  String? areaOrLandmark,
  String? reverseGeocoded,
}) {
  final area = (areaOrLandmark ?? '').trim();
  final cityName = (city ?? '').trim();
  final geocoded = (reverseGeocoded ?? '').trim();

  final parts = <String>[];
  if (area.isNotEmpty) parts.add(area);
  if (cityName.isNotEmpty) parts.add(cityName);

  final composed = parts.join(', ');
  if (composed.isNotEmpty) return composed;

  // Nothing chosen by hand: fall back to whatever the reverse lookup found, so
  // the saved row is still readable.
  return geocoded;
}

/// What the customer has selected so far, and whether it may be confirmed.
///
/// [latitude] and [longitude] come from the map camera, so they are null while
/// the map is still starting (or when it could not start at all). The same
/// plausibility rules the GPS capture uses are applied here, which is what
/// stops a `0,0` fix — the coordinates a device reports when it has no fix —
/// from being confirmed and stored as a real delivery address.
bool canConfirmMapPick({
  required double? latitude,
  required double? longitude,
  required bool hasUsableAddressText,
}) {
  if (latitude == null || longitude == null) return false;
  if (!CapturedCoordinates.isPlausibleEarth(latitude, longitude)) return false;
  return hasUsableAddressText;
}

/// The coordinates shown to the customer under the pin, to five decimal places
/// (roughly a metre), which is more than GPS accuracy can honestly offer.
String formatPickedCoordinates({
  required double? latitude,
  required double? longitude,
}) {
  if (latitude == null || longitude == null) return 'Coordinates unavailable';
  return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
}
