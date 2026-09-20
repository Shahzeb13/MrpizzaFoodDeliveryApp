import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';

class AuthStateModel {
  final bool isAuthenticated;
  final User? user;
  final bool isLoading;
  final bool isInitializing;
  final String? errorMessage;

  const AuthStateModel({
    this.isAuthenticated = false,
    this.user,
    this.isLoading = false,
    this.isInitializing = true,
    this.errorMessage,
  });

  AuthStateModel copyWith({
    bool? isAuthenticated,
    User? user,
    bool? isLoading,
    bool? isInitializing,
    String? errorMessage,
  }) {
    return AuthStateModel(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      isInitializing: isInitializing ?? this.isInitializing,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthStateModel> {
  final AuthRepository _repo;
  late final StreamSubscription<AuthState> _authSubscription;
  bool _isHandlingSignup = false;

  AuthNotifier(this._repo) : super(const AuthStateModel()) {
    // Single listener for the lifetime of the app. It reacts to every auth
    // transition (login, post-signup session, token expiry -> signedOut) so
    // navigation is driven from one place via the router.
    _authSubscription = _repo.onAuthStateChange.listen(_onAuthChange);

    // Safety net: never splash forever if the initial session event misses.
    Future.delayed(const Duration(seconds: 3), () {
      if (state.isInitializing) {
        _applySession(_repo.currentSession);
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  void _applySession(Session? session) {
    state = state.copyWith(
      isInitializing: false,
      isAuthenticated: session != null,
      user: session?.user,
    );
  }

  void _onAuthChange(AuthState change) {
    switch (change.event) {
      case AuthChangeEvent.initialSession:
        _applySession(change.session);
        break;
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
        // During signup the profile row is created before we allow
        // navigation; otherwise the user could land on /home with no profile.
        if (_isHandlingSignup) break;
        state = state.copyWith(
          isInitializing: false,
          isAuthenticated: true,
          user: change.session?.user,
          errorMessage: null,
        );
        break;
      case AuthChangeEvent.signedOut:
        state = const AuthStateModel(isInitializing: false);
        break;
      default:
        break; // userUpdated, passwordRecovery, mfaChallenge... handled elsewhere
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _repo.signIn(email: email.trim(), password: password);
      state = AuthStateModel(
          isAuthenticated: true, user: res.user, isInitializing: false);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
          isLoading: false,
          errorMessage: 'Something went wrong. Please try again.');
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
    _isHandlingSignup = true;
    try {
      final res = await _repo.signUp(email: email.trim(), password: password);
      final user = res.user;
      if (user == null) {
        state = state.copyWith(
            isLoading: false, errorMessage: 'Signup failed. Please try again.');
        return false;
      }

      try {
        await _repo.insertProfile(
            userId: user.id, fullName: name.trim(), phone: phone.trim());
      } catch (e) {
        await _repo.signOut();
        state = state.copyWith(
            isLoading: false,
            errorMessage: 'Failed to create profile. Please try again.');
        return false;
      }

      state = AuthStateModel(
          isAuthenticated: true, user: user, isInitializing: false);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(
          isLoading: false,
          errorMessage: 'Something went wrong. Please try again.');
      return false;
    } finally {
      _isHandlingSignup = false;
    }
  }

  void logout() {
    _repo.signOut();
  }
}

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthStateModel>((ref) {
  return AuthNotifier(AuthRepository());
});
