import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/profile/providers/profile_provider.dart';

/// The role a user operates as, as recorded in `profiles.role`.
enum UserRole { customer, rider }

/// Maps the raw `profiles.role` text column onto a [UserRole].
///
/// The database constrains the column to exactly 'customer' or 'rider'. Any
/// other value — null, blank, or a label this build does not recognise — falls
/// back to [UserRole.customer], the only panel that is safe to expose before a
/// role is known.
UserRole userRoleFromDatabaseValue(String? rawRole) {
  switch (rawRole?.trim().toLowerCase()) {
    case 'rider':
      return UserRole.rider;
    default:
      return UserRole.customer;
  }
}

/// The signed-in user's role, resolved from the `profiles` table.
///
/// This provider is the single source of truth for role in the app: the value
/// always comes from the database row belonging to the signed-in user. It is
/// never a default that navigation guesses at, so the router cannot send a
/// rider to the customer panel while the role is still unknown — the router
/// waits for this future instead.
class RoleNotifier extends AsyncNotifier<UserRole> {
  @override
  Future<UserRole> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      // Signed out: there is no row to read, and nothing behind the router
      // renders a role surface. Returning immediately also keeps the startup
      // splash from waiting on a query that cannot run.
      return UserRole.customer;
    }

    final profile =
        await ref.watch(profileRepositoryProvider).fetchProfile(userId);
    return userRoleFromDatabaseValue(profile?.role);
  }

  /// Re-reads the role from the database, e.g. after it is changed server-side.
  Future<UserRole> reload() => ref.refresh(roleProvider.future);
}

final roleProvider =
    AsyncNotifierProvider<RoleNotifier, UserRole>(RoleNotifier.new);
