/// Profile feature models.
library;

/// The user's profile row from the `profiles` table.
class UserProfile {
  final String id;
  final String fullName;
  final String phone;
  final String role;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    this.role = 'customer',
    this.createdAt,
    this.updatedAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      fullName: (map['full_name'] as String?) ?? '',
      phone: (map['phone'] as String?) ?? '',
      role: (map['role'] as String?) ?? 'customer',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }
}

/// A saved delivery address from the `addresses` table.
class UserAddress {
  final String id;
  final String userId;
  final String label;
  final String addressLine;
  final double? latitude;
  final double? longitude;
  final bool isDefault;
  final DateTime? createdAt;

  const UserAddress({
    required this.id,
    required this.userId,
    required this.label,
    required this.addressLine,
    this.latitude,
    this.longitude,
    this.isDefault = false,
    this.createdAt,
  });

  factory UserAddress.fromMap(Map<String, dynamic> map) {
    return UserAddress(
      id: map['id'] as String,
      userId: (map['user_id'] as String?) ?? '',
      label: (map['label'] as String?) ?? '',
      addressLine: (map['address_line'] as String?) ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      isDefault: (map['is_default'] as bool?) ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }
}
