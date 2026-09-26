import '../../../core/geo/geo.dart';
import '../models/profile.dart';

/// What should happen when the customer picks a location.
///
/// The app used to hold the chosen pin in memory only, so nothing ever reached
/// the `addresses` table: My Addresses stayed empty and checkout had nothing to
/// attach an order to. Every location selection now goes through here.
class LocationSelectionOutcome {
  /// The saved address this selection matched, when it was already on file.
  final UserAddress? existing;

  /// The label to store, derived from the address text.
  final String label;

  /// True when no saved address matched and a new row is needed.
  final bool shouldInsert;

  /// True when this is the customer's first address, so it should also become
  /// their default. Checkout needs a default to have something selected.
  final bool shouldBecomeDefault;

  const LocationSelectionOutcome({
    required this.existing,
    required this.label,
    required this.shouldInsert,
    required this.shouldBecomeDefault,
  });
}

/// Decides whether a location the customer just picked is somewhere new or a
/// place already in their address book.
///
/// The decisions are static and pure so they can be tested without a database;
/// doing the insert is the caller's job.
class AddressBook {
  const AddressBook._();

  /// Two points closer than this are treated as the same place, so re-picking a
  /// spot does not create a near-duplicate row. Roughly the width of a house.
  static const double duplicateRadiusMetres = 50;

  /// Longest label derived from address text, so a card does not grow a wall of
  /// words.
  static const int maximumLabelLength = 28;

  /// A short, human label for an address, taken from the text itself so the
  /// customer is never asked to invent one.
  ///
  /// "Triple one hotel near comsats" becomes "Triple one". Casing is left as the
  /// map or the customer wrote it, because re-casing proper nouns guesses wrong.
  static String deriveLabel(
    String addressLine, {
    String fallback = 'Current Location',
  }) {
    final cleaned = addressLine
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.isEmpty) return fallback;

    // The tail of a postal address is the city or area, which repeats on every
    // row and tells the customer nothing. Keep the first two comma segments.
    final segments = cleaned
        .split(',')
        .map((s) => s.replaceAll(RegExp(r'[\s;]+'), ' ').trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (segments.isEmpty) return fallback;
    // Three or more segments means the extra ones are area/city noise, and the
    // first two carry the street detail worth keeping. Exactly two segments is
    // the common "<place>, <city>" shape, so the city is the one to drop.
    if (segments.length >= 3) {
      return _capLength('${segments[0]}, ${segments[1]}');
    }
    if (segments.length == 2) return _capLength(segments.first);

    // Otherwise take the opening words, which is where a name or a house
    // number lives ("Triple one hotel near comsats" -> "Triple one").
    final words = segments.first.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return fallback;
    return _capLength(words.take(2).join(' '));
  }

  static String _capLength(String value) {
    if (value.length <= maximumLabelLength) return value;
    return '${value.substring(0, maximumLabelLength - 1).trimRight()}…';
  }

  /// The already-saved address at (or within [duplicateRadiusMetres] of) this
  /// point, or null. Addresses without coordinates can never match a point.
  static UserAddress? findExistingAtPoint({
    required List<UserAddress> saved,
    required double? latitude,
    required double? longitude,
  }) {
    if (latitude == null || longitude == null || saved.isEmpty) return null;

    UserAddress? closest;
    var closestMetres = double.infinity;

    for (final address in saved) {
      final addressLat = address.latitude;
      final addressLng = address.longitude;
      if (addressLat == null || addressLng == null) continue;

      final metres = Geo.haversineMetres(addressLat, addressLng, latitude, longitude);
      if (metres < closestMetres) {
        closestMetres = metres;
        closest = address;
      }
    }

    if (closest == null) return null;
    return closestMetres <= duplicateRadiusMetres ? closest : null;
  }

  /// The already-saved address with this exact text, or null. Used when a typed
  /// address carries no coordinates, so distance cannot be the test.
  static UserAddress? findExistingByText({
    required List<UserAddress> saved,
    required String addressLine,
  }) {
    final needle = _normalise(addressLine);
    if (needle.isEmpty) return null;

    for (final address in saved) {
      if (_normalise(address.addressLine) == needle) return address;
    }
    return null;
  }

  static String _normalise(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  /// Decides what to do with a freshly chosen location.
  ///
  /// Prefers a positional match when there is a pin, because two different
  /// addresses can share a name while one address can have several names typed
  /// for it. Falls back to comparing the text when there is no pin.
  static LocationSelectionOutcome classifyLocationSelection({
    required List<UserAddress> saved,
    required String addressLine,
    required double? latitude,
    required double? longitude,
  }) {
    final existing = findExistingAtPoint(
      saved: saved,
      latitude: latitude,
      longitude: longitude,
    ) ??
        findExistingByText(saved: saved, addressLine: addressLine);

    return LocationSelectionOutcome(
      existing: existing,
      label: deriveLabel(addressLine),
      shouldInsert: existing == null,
      shouldBecomeDefault: existing == null && saved.isEmpty,
    );
  }
}
