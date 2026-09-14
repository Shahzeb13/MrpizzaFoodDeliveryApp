import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../data/profile_repository.dart';
import '../models/profile.dart';

final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => ProfileRepository());

/// The current user id, or null while signed out.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).user?.id;
});

/// The signed-in user's profile row (refreshed by invalidating this provider).
final profileFutureProvider = FutureProvider<UserProfile?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;
  return ref.watch(profileRepositoryProvider).fetchProfile(userId);
});

/// The signed-in user's saved addresses (refreshed by invalidating this provider).
final addressesFutureProvider = FutureProvider<List<UserAddress>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const [];
  return ref.watch(profileRepositoryProvider).fetchAddresses(userId);
});
