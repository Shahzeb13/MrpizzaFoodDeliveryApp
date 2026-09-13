import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';

class AuthState {
  final bool isAuthenticated;
  final UserModel? user;
  final bool isLoading;
  final String? errorMessage;

  const AuthState({
    this.isAuthenticated = true, // Default to demo logged-in user
    this.user = const UserModel(
      id: 'usr_101',
      name: 'Alex Morgan',
      email: 'alex.morgan@mrpizza.com',
      phone: '+1 (555) 234-5678',
      vipPoints: 450,
      role: 'customer',
    ),
    this.isLoading = false,
    this.errorMessage,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    UserModel? user,
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
  AuthNotifier() : super(const AuthState());

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    await Future.delayed(const Duration(milliseconds: 600));

    if (email.trim().isEmpty || password.isEmpty) {
      state = state.copyWith(isLoading: false, errorMessage: 'Please fill in all fields.');
      return false;
    }

    final user = UserModel(
      id: 'usr_101',
      name: email.contains('@') ? email.split('@')[0].toUpperCase() : 'Valued Guest',
      email: email.trim(),
      phone: '+1 (555) 987-6543',
      vipPoints: 500,
    );

    state = state.copyWith(
      isAuthenticated: true,
      user: user,
      isLoading: false,
    );
    return true;
  }

  Future<bool> signup({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    await Future.delayed(const Duration(milliseconds: 600));

    if (name.trim().isEmpty || email.trim().isEmpty || password.isEmpty) {
      state = state.copyWith(isLoading: false, errorMessage: 'Please complete all required fields.');
      return false;
    }

    final newUser = UserModel(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      email: email.trim(),
      phone: phone.trim().isEmpty ? '+1 (555) 000-1122' : phone.trim(),
      vipPoints: 100, // Welcome bonus points!
    );

    state = state.copyWith(
      isAuthenticated: true,
      user: newUser,
      isLoading: false,
    );
    return true;
  }

  void logout() {
    state = const AuthState(
      isAuthenticated: false,
      user: null,
      isLoading: false,
    );
  }
}

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});