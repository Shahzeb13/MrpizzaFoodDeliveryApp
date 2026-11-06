import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/role_select_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/menu/screens/menu_screen.dart';
import '../../features/orders/screens/my_orders_screen.dart';
import '../../features/orders/screens/order_tracking_screen.dart';
import '../../features/payment/screens/apply_discount_screen.dart';
import '../../features/payment/screens/checkout_screen.dart';
import '../../features/payment/screens/payment_method_screen.dart';
import '../../features/profile/screens/account_deletion_screen.dart';
import '../../features/profile/screens/addresses_screen.dart';
import '../../features/profile/screens/favorites_screen.dart';
import '../../features/profile/screens/loyalty_points_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/support_center_screen.dart';
import '../../features/profile/screens/support_document_screen.dart';
import '../../features/profile/screens/wallet_screen.dart';
import '../../features/profile/models/support_document.dart';
import '../providers/role_provider.dart';
import 'route_guard.dart';
import '../../features/rider/screens/rider_history_screen.dart';
import '../../features/rider/screens/rider_screen.dart';

/// Where the app opens for a given session.
///
/// A signed-in user starts on the panel their `profiles.role` row selects, so
/// a rider never lands in the customer panel. A signed-out visitor starts on
/// the store front rather than the login screen: the menu is browsable without
/// an account, and login is asked only when a screen needs one.
String initialLocationForSession({
  required bool isAuthenticated,
  required UserRole role,
}) =>
    isAuthenticated ? landingLocationForRole(role) : customerLandingLocation;

/// Auth- and role-driven router.
///
/// The GoRouter below is created exactly once, and the login/signup redirect
/// and post-signup resume all flow through the single `redirect` callback it
/// owns (`resolveAuthorizedLocation`, which re-reads the live session on every
/// navigation). Re-creating the whole router on each auth flip — the previous
/// mechanism — restarted navigation at the landing panel, which by design
/// cannot honour a "return to checkout" target carried in a query parameter.
///
/// Instead, auth and role changes mark the router stale, and `refresh()` makes
/// the guard re-run for whatever screen is open at that moment:
/// - sign-in on `/login?return=/checkout` resumes the checkout, or lands on
///   the role's panel when there is nothing to resume;
/// - token expiry on a protected screen re-routes to login with the screen
///   carried along as the new `?return=`;
/// - sign-out on the menu simply keeps browsing as a guest.
final routerProvider = Provider<GoRouter>((ref) {
  // Read once, at first watch. AuthGate mounts the router only after the
  // startup session and role lookups have settled, so these values describe
  // the first frame truthfully; every later change flows through refresh().
  final startupAuth = ref.read(authStateProvider);
  final startupRole = ref.read(roleProvider).value ?? UserRole.customer;

  final router = GoRouter(
    initialLocation: initialLocationForSession(
      isAuthenticated:
          startupAuth.isAuthenticated && !startupAuth.isLoading,
      role: startupRole,
    ),
    redirect: (context, state) {
      // Read live values rather than the captured ones: this closure outlives
      // the frame it was built for, and the guard must reflect the current
      // session on every navigation.
      final auth = ref.read(authStateProvider);
      final roleState = ref.read(roleProvider);
      return resolveAuthorizedLocation(
        isAuthenticated: auth.isAuthenticated && !auth.isLoading,
        role: roleState.value ?? UserRole.customer,
        isRoleLoading: roleState.isLoading,
        requestedLocation: state.matchedLocation,
        returnTarget: state.uri.queryParameters['return'],
      );
    },
    routes: [
      GoRoute(
        path: loginLocation,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: signupLocation,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: roleSelectLocation,
        builder: (context, state) => const RoleSelectScreen(),
      ),
      GoRoute(
        path: forgotPasswordLocation,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: customerLandingLocation,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: menuLocation,
        builder: (context, state) => const MenuScreen(),
      ),
      GoRoute(
        path: trackOrderLocation,
        builder: (context, state) => const OrderTrackingScreen(),
      ),
      GoRoute(
        path: myOrdersLocation,
        builder: (context, state) => const MyOrdersScreen(),
      ),
      GoRoute(
        path: walletLocation,
        builder: (context, state) => const WalletScreen(),
      ),
      GoRoute(
        path: loyaltyLocation,
        builder: (context, state) => const LoyaltyPointsScreen(),
      ),
      GoRoute(
        path: addressesLocation,
        builder: (context, state) => const AddressesScreen(),
      ),
      GoRoute(
        path: favoritesLocation,
        builder: (context, state) => const FavoritesScreen(),
      ),
      GoRoute(
        path: supportCenterLocation,
        // "Problem with this order?" pushes here with the order's bill number
        // as `extra`, so the support email can carry it in its subject. Any
        // other extra type is ignored rather than trusted.
        builder: (context, state) => SupportCenterScreen(
          orderReference: state.extra is String && (state.extra as String).isNotEmpty
              ? state.extra as String
              : null,
        ),
        routes: [
          // Policies and FAQs live on the website, so this route carries which
          // document to show rather than its URL. Only the documents declared in
          // SupportDocument can be opened; anything else redirects back to the
          // Support Center instead of loading an arbitrary address.
          GoRoute(
            path: 'document/:document',
            redirect: (context, state) =>
                SupportDocument.fromSlug(state.pathParameters['document']) ==
                        null
                    ? supportCenterLocation
                    : null,
            builder: (context, state) => SupportDocumentScreen(
              document: SupportDocument.fromSlug(
                state.pathParameters['document'],
              )!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: deleteAccountLocation,
        builder: (context, state) => const AccountDeletionScreen(),
      ),
      GoRoute(
        path: checkoutLocation,
        builder: (context, state) => const CheckoutScreen(),
      ),
      GoRoute(
        path: applyDiscountLocation,
        builder: (context, state) => const ApplyDiscountScreen(),
      ),
      GoRoute(
        path: paymentMethodLocation,
        builder: (context, state) => const PaymentMethodScreen(),
      ),
      GoRoute(
        path: riderLandingLocation,
        builder: (context, state) => const RiderScreen(),
      ),
      GoRoute(
        path: riderHistoryLocation,
        builder: (context, state) => const RiderHistoryScreen(),
      ),
      GoRoute(
        path: profileLocation,
        builder: (context, state) => const ProfileScreen(),
      ),
    ],
  );

  // The one way navigation reacts to a session change: every auth or role
  // event re-runs the guard for the screen currently open. Auth changes fire
  // for token refreshes too, which only ever re-confirms an already-allowed
  // screen, so the extra redirect pass is cheap and harmless.
  void refreshNavigationAfterSessionChange() => router.refresh();
  ref.listen(authStateProvider,
      (_, __) => refreshNavigationAfterSessionChange());
  ref.listen(roleProvider, (_, __) => refreshNavigationAfterSessionChange());

  ref.onDispose(router.dispose);
  return router;
});
