import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/supabase_client.dart';

class AuthRepository {
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    return supabase.auth.signUp(email: email, password: password);
  }

  Future<void> insertProfile({
    required String userId,
    required String fullName,
    required String phone,
  }) {
    return supabase.from('profiles').insert({
      'id': userId,
      'full_name': fullName,
      'phone': phone,
      'role': 'customer',
    });
  }

  Future<void> signOut() => supabase.auth.signOut();

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return supabase.auth.signInWithPassword(email: email, password: password);
  }

  User? get currentUser => supabase.auth.currentUser;
}
