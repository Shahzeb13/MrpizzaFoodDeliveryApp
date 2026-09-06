/// Guards navigation based on the current user role.
///
/// For this stage it is a placeholder. Real auth-based guarding is added in a
/// later stage when login and roles are actually enforced.
class RouteGuard {
  RouteGuard._();

  static bool isLoggedIn() {
    // TODO: Replace with real auth check in a later stage.
    return true;
  }

  static bool canAccessRiderRoutes() {
    // TODO: Replace with real role check in a later stage.
    return true;
  }
}
