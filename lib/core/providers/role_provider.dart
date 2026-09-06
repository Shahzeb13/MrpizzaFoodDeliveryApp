import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The role a user is operating as in this single-restaurant app.
enum UserRole { customer, rider }

/// Tracks the active user role.
///
/// For this stage it is a hardcoded toggleable mock role (no real auth).
/// Defaults to customer.
class RoleNotifier extends Notifier<UserRole> {
  @override
  UserRole build() => UserRole.customer;

  void setRole(UserRole role) => state = role;
}

final roleProvider = NotifierProvider<RoleNotifier, UserRole>(RoleNotifier.new);