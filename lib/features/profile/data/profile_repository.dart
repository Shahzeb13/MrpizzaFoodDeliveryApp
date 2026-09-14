import '../../../core/network/supabase_client.dart';
import '../models/profile.dart';

class ProfileRepository {
  Future<UserProfile?> fetchProfile(String userId) async {
    final res =
        await supabase.from('profiles').select().eq('id', userId).maybeSingle();
    if (res == null) return null;
    return UserProfile.fromMap(res);
  }

  Future<void> updateProfile({
    required String userId,
    required String fullName,
    required String phone,
  }) {
    return supabase.from('profiles').update({
      'full_name': fullName,
      'phone': phone,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  Future<List<UserAddress>> fetchAddresses(String userId) async {
    final res = await supabase
        .from('addresses')
        .select()
        .eq('user_id', userId)
        .order('is_default', ascending: false)
        .order('created_at', ascending: true);
    return (res as List)
        .map((row) => UserAddress.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> addAddress({
    required String userId,
    required String label,
    required String addressLine,
    double? latitude,
    double? longitude,
  }) {
    return supabase.from('addresses').insert({
      'user_id': userId,
      'label': label,
      'address_line': addressLine,
      'latitude': latitude,
      'longitude': longitude,
      'is_default': false,
    });
  }

  /// Marks [addressId] as the single default for the user by clearing
  /// `is_default` on all the user's other addresses first.
  Future<void> setDefaultAddress({
    required String userId,
    required String addressId,
  }) async {
    await supabase
        .from('addresses')
        .update({'is_default': false}).eq('user_id', userId);
    await supabase
        .from('addresses')
        .update({'is_default': true})
        .eq('id', addressId)
        .eq('user_id', userId);
  }

  Future<void> deleteAddress(String addressId) {
    return supabase.from('addresses').delete().eq('id', addressId);
  }
}
