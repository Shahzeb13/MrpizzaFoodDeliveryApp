import '../providers/role_provider.dart';

/// The customer's landing panel.
const customerLandingLocation = '/home';

/// The rider's landing panel.
const riderLandingLocation = '/rider';

const loginLocation = '/login';

const signupLocation = '/signup';

const roleSelectLocation = '/role_select';

/// Screens reachable without a session. Everything else requires a signed-in
/// user, so a deep link cannot drop a visitor straight into the app.
const publicLocations = <String>{
  loginLocation,
  signupLocation,
  roleSelectLocation,
};

const riderHistoryLocation = '/rider/history';

const riderEarningsLocation = '/rider/earnings';

/// Screens that only a signed-in rider may open.
const riderOnlyLocations = <String>{
  riderLandingLocation,
  riderHistoryLocation,
  riderEarningsLocation,
};

/// The first screen a user with [role] should see.
String landingLocationForRole(UserRole role) =>
    role == UserRole.rider ? riderLandingLocation : customerLandingLocation;

/// Decides whether [requestedLocation] may be shown for the given session, and
/// returns the location to show instead when it may not.
///
/// Returns null when the navigation is allowed. This is a pure function so the
/// rule is testable on its own and so the router can call it with live session
/// values on every navigation.
String? resolveAuthorizedLocation({
  required bool isAuthenticated,
  required UserRole role,
  required String requestedLocation,
}) {
  if (publicLocations.contains(requestedLocation)) {
    // A signed-in user has no business on the login/signup screens; send them
    // to the panel their database role belongs to.
    return isAuthenticated ? landingLocationForRole(role) : null;
  }

  if (!isAuthenticated) {
    return loginLocation;
  }

  if (riderOnlyLocations.contains(requestedLocation) && role != UserRole.rider) {
    return landingLocationForRole(role);
  }

  return null;
}
