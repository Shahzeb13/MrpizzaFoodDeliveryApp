import 'dart:math' as math;

/// Great-circle helpers shared by the branch picker and the address book, so
/// "how far apart are these two points" is answered the same way everywhere.
class Geo {
  const Geo._();

  /// Haversine distance in kilometres between two lat/lng points.
  static double haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    double toRadians(double deg) => deg * (math.pi / 180.0);

    final dLat = toRadians(lat2 - lat1);
    final dLon = toRadians(lon2 - lon1);

    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(toRadians(lat1)) *
            math.cos(toRadians(lat2)) *
            math.pow(math.sin(dLon / 2), 2);

    return earthRadiusKm * 2 * math.asin(math.sqrt(a));
  }

  /// Same distance in metres, which is the unit a human thinks in when asking
  /// "is this the same place I already saved?".
  static double haversineMetres(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) =>
      haversineKm(lat1, lon1, lat2, lon2) * 1000;
}
