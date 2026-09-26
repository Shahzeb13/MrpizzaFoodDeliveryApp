import '../../../core/geo/geo.dart';
import '../../profile/models/profile.dart';

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
  static double haversineKm(double lat1, double lon1, double lat2, double lon2) =>
      Geo.haversineKm(lat1, lon1, lat2, lon2);
}

/// Outcome of trying to pick the branch nearest to a delivery address.
///
/// [isNearestToAddress] is false whenever we could not prove a branch was the
/// closest one — either because the address has no coordinates yet, or because
/// the branch records have no coordinates. Callers must not describe the branch
/// as "nearest" in that case.
class BranchSelection {
  final Branch? branch;
  final bool isNearestToAddress;

  const BranchSelection({required this.branch, required this.isNearestToAddress});

  static const BranchSelection none =
      BranchSelection(branch: null, isNearestToAddress: false);

  /// Picks the branch with the smallest straight-line distance to [address].
  ///
  /// Requires coordinates on both sides. When either side is missing, no
  /// nearest branch is claimed: [branch] is left null for an unpinned address
  /// (the customer must choose) and falls back to the first branch when only
  /// the branch records are missing coordinates.
  static BranchSelection selectNearestBranch(
    UserAddress address,
    List<Branch> branches,
  ) {
    return selectNearestBranchToPoint(
      latitude: address.latitude,
      longitude: address.longitude,
      branches: branches,
    );
  }

  /// Picks the branch closest to a raw coordinate, with no saved address
  /// involved.
  ///
  /// This is the path a live map pin takes: the customer chose a position on
  /// screen, so the closest branch can be worked out even when nothing has been
  /// saved to the `addresses` table yet. When no branch carries coordinates
  /// the first branch is returned but no nearest claim is made, because nothing
  /// was actually compared.
  static BranchSelection selectNearestBranchToPoint({
    required double? latitude,
    required double? longitude,
    required List<Branch> branches,
  }) {
    if (branches.isEmpty) return none;
    if (latitude == null || longitude == null) return none;

    Branch? nearest;
    var minDistance = double.infinity;
    for (final branch in branches) {
      final distance = branch.distanceTo(latitude, longitude);
      if (distance == null) continue;
      if (distance < minDistance) {
        minDistance = distance;
        nearest = branch;
      }
    }

    if (nearest != null) {
      return BranchSelection(branch: nearest, isNearestToAddress: true);
    }
    return BranchSelection(
      branch: branches.first,
      isNearestToAddress: false,
    );
  }
}