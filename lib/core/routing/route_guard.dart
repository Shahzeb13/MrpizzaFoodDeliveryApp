import '../providers/role_provider.dart';

/// The customer's landing panel.
const customerLandingLocation = '/home';

/// The rider's landing panel.
const riderLandingLocation = '/rider';

const loginLocation = '/login';

const signupLocation = '/signup';

const roleSelectLocation = '/role_select';

const forgotPasswordLocation = '/forgot-password';

/// Named routes, one const per path so the guard and the router cannot drift.
const menuLocation = '/menu';

const profileLocation = '/profile';

const supportCenterLocation = '/support';

const checkoutLocation = '/checkout';

const applyDiscountLocation = '/apply-discount';

const paymentMethodLocation = '/payment-method';

const trackOrderLocation = '/orders/track';

const myOrdersLocation = '/my-orders';

const walletLocation = '/wallet';

const loyaltyLocation = '/loyalty';

const addressesLocation = '/addresses';

const favoritesLocation = '/favorites';

const deleteAccountLocation = '/delete-account';

const riderHistoryLocation = '/rider/history';

/// Screens a signed-out visitor may open. The store front — menu, cart, the
/// account-independent pages — works without an account; login is asked only
/// when the visit actually needs one (checkout, the customer's data screens).
const publicLocations = <String>{
  customerLandingLocation,
  menuLocation,
  profileLocation,
  supportCenterLocation,
};

/// The auth screens, whose only purpose is signing in or up. They are public
/// because a guest needs exactly these — and a signed-in user lingering on
/// one has finished their business with it, so the guard moves them along.
const authScreenLocations = <String>{
  loginLocation,
  signupLocation,
  roleSelectLocation,
  forgotPasswordLocation,
};

/// Open roots whose sub-paths are public too: the policy and FAQ documents
/// under `/support/document/:slug` are browsable signed out.
const publicLocationPrefixes = <String>[supportCenterLocation];

/// Screens that only a signed-in rider may open.
const riderOnlyLocations = <String>{
  riderLandingLocation,
  riderHistoryLocation,
};

/// The commerce screens a rider has no business in: checkout and everything
/// that exists to serve an order a customer is buying. A rider deep-linking
/// one of these is returned to the rider panel rather than shown a customer
/// flow built on `profiles.role` data their account does not have.
const customerOnlyLocations = <String>{
  checkoutLocation,
  applyDiscountLocation,
  paymentMethodLocation,
  trackOrderLocation,
  loyaltyLocation,
  favoritesLocation,
};

/// The customer store front: open when signed out, closed to a rider signed
/// into their own panel. A rider account delivers orders — it has no cart,
/// no checkout, nothing the storefront builds its screens around — so its
/// side of the app is the rider panel alone.
const customerStorefrontLocations = <String>{
  customerLandingLocation,
  menuLocation,
};

/// Everything a signed-in rider is kept out of: the store front and the
/// commerce screens it serves. One set so the deep-link guard and the login
/// resume check cannot drift apart.
const riderClosedLocations = <String>{
  ...customerStorefrontLocations,
  ...customerOnlyLocations,
};

/// Places a login/signup screen may send a user back to after they sign in.
///
/// The `?return=` query parameter came from this app's own redirect, so the
/// list is closed on purpose: a hand-typed or crafted value never navigates
/// anywhere the app does not have a route for.
const resumableLocations = <String>{
  customerLandingLocation,
  menuLocation,
  profileLocation,
  supportCenterLocation,
  checkoutLocation,
  applyDiscountLocation,
  paymentMethodLocation,
  trackOrderLocation,
  myOrdersLocation,
  walletLocation,
  loyaltyLocation,
  addressesLocation,
  favoritesLocation,
  deleteAccountLocation,
  riderLandingLocation,
  riderHistoryLocation,
};

/// The first screen a user with [role] should see.
String landingLocationForRole(UserRole role) =>
    role == UserRole.rider ? riderLandingLocation : customerLandingLocation;

/// True when the query parameter carried back to login names a route the app
/// can actually open, so the resume step cannot navigate off-script.
String? validatedReturnTarget(String? raw) {
  if (raw == null) return null;
  if (!resumableLocations.contains(raw)) return null;
  return raw;
}

/// True when a signed-in user with [role] may land on [returnTarget] from a
/// login screen. A rider handed back `/checkout` has nowhere in it to go, so
/// the resume is dropped and they land on the rider panel instead.
bool returnTargetAllowedForRole(String returnTarget, UserRole role) {
  if (role == UserRole.rider && riderClosedLocations.contains(returnTarget)) {
    return false;
  }
  if (role != UserRole.rider && riderOnlyLocations.contains(returnTarget)) {
    return false;
  }
  return true;
}

/// Decides whether [requestedLocation] may be shown for the given session, and
/// returns the location to show instead when it may not.
///
/// Returns null when the navigation is allowed. This is a pure function so the
/// rule is testable on its own and so the router can call it with live session
/// values on every navigation.
///
/// [returnTarget] is the `?return=` value the login screen carries from an
/// earlier redirect of exactly this kind: a customer tapped Checkout signed
/// out, the guard sent them to `/login?return=/checkout`, and after they sign
/// in the same function sends them on to checkout to finish what they started.
String? resolveAuthorizedLocation({
  required bool isAuthenticated,
  required UserRole role,
  required String requestedLocation,
  String? returnTarget,
  bool isRoleLoading = false,
}) {
  // A role that is still being read from `profiles` cannot be trusted to pick
  // a panel: deciding now could commit a rider to the customer app and strand
  // them there. Staying put is safe — the splash gate covers this window for
  // the user, and the guard runs again when the role lands.
  if (isAuthenticated && isRoleLoading) return null;

  // The store front is public, but only to the visits that have no panel of
  // their own: a rider signed into their account is kept on their side, so
  // the storefront screens hand them straight back to the rider panel. This
  // check runs before the public allow, which reads the storefront as open.
  if (isAuthenticated &&
      role == UserRole.rider &&
      customerStorefrontLocations.contains(requestedLocation)) {
    return riderLandingLocation;
  }

  if (publicLocations.contains(requestedLocation)) {
    // The store front belongs to everyone, signed in or not: arriving here
    // from a link is normal use, not something to be redirected out of.
    return null;
  }

  for (final prefix in publicLocationPrefixes) {
    if (requestedLocation.startsWith(prefix)) return null;
  }

  if (authScreenLocations.contains(requestedLocation)) {
    // A signed-in user has no business camping on the login/signup screens.
    // The `?return=` target wins when it is real — that is the checkout being
    // resumed — and only when this account's role may actually open it;
    // otherwise they land on the panel their role selects.
    if (!isAuthenticated) return null;
    final resumeTo = validatedReturnTarget(returnTarget);
    if (resumeTo != null && returnTargetAllowedForRole(resumeTo, role)) {
      return resumeTo;
    }
    return landingLocationForRole(role);
  }

  if (!isAuthenticated) {
    // Everything that needs an account visits the login screen with the
    // requested place carried along, so a completed sign-in resumes the
    // interrupted journey instead of restarting at the menu.
    return '$loginLocation?return=${Uri.encodeComponent(requestedLocation)}';
  }

  if (riderOnlyLocations.contains(requestedLocation) && role != UserRole.rider) {
    return landingLocationForRole(role);
  }

  if (customerOnlyLocations.contains(requestedLocation) &&
      role == UserRole.rider) {
    return riderLandingLocation;
  }

  return null;
}
