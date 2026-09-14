import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';

class AuthState {
  final bool isAuthenticated;
  final User? user;
  final bool isLoading;
  final String? errorMessage;

  const AuthState({
    this.isAuthenticated = false,
    this.user,
    this.isLoading = false,
    this.errorMessage,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    User? user,
    bool? isLoading,
    String? errorMessage,
  }) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repo;

  AuthNotifier(this._repo) : super(const AuthState()) {
    final user = _repo.currentUser;
    if (user != null) {
      state = AuthState(isAuthenticated: true, user: user);
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _repo.signIn(email: email.trim(), password: password);
      state = AuthState(isAuthenticated: true, user: res.user);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Something went wrong. Please try again.');
      return false;
    }
  }

  Future<bool> signup({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _repo.signUp(email: email.trim(), password: password);
      final user = res.user;
      if (user == null) {
        state = state.copyWith(isLoading: false, errorMessage: 'Signup failed. Please try again.');
        return false;
      }

      try {
        await _repo.insertProfile(userId: user.id, fullName: name.trim(), phone: phone.trim());
      } catch (e) {
        await _repo.signOut();
        state = state.copyWith(isLoading: false, errorMessage: 'Failed to create profile. Please try again.');
        return false;
      }

      state = AuthState(isAuthenticated: true, user: user);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Something went wrong. Please try again.');
      return false;
    }
  }

  void logout() {
    _repo.signOut();
    state = const AuthState();
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(AuthRepository());
});
