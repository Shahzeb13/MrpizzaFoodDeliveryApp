import 'dart:math' as math;

/// A restaurant branch from the `branches` table.
class Branch {
  final String id;
  final String name;
  final double? latitude;
  final double? longitude;

  const Branch({
    required this.id,
    required this.name,
    this.latitude,
    this.longitude,
  });

  factory Branch.fromMap(Map<String, dynamic> map) {
    return Branch(
      id: map['id'] as String,
      name: (map['name'] as String?) ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
    );
  }

  /// Great-circle distance (km) from this branch to a point.
  double? distanceTo(double lat, double lng) {
    final branchLat = latitude;
    final branchLng = longitude;
    if (branchLat == null || branchLng == null) return null;
    return haversineKm(branchLat, branchLng, lat, lng);
  }

  /// Haversine distance in kilometers between two lat/lng points.
  static double haversineKm(double lat1, double lon1, double lat2, double lon2) {
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
}