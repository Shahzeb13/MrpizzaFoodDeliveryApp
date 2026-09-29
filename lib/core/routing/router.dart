import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/role_select_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/menu/screens/menu_screen.dart';
import '../../features/orders/screens/my_orders_screen.dart';
import '../../features/orders/screens/order_tracking_screen.dart';
import '../../features/payment/screens/checkout_screen.dart';
import '../../features/profile/screens/account_deletion_screen.dart';
import '../../features/profile/screens/addresses_screen.dart';
import '../../features/profile/screens/favorites_screen.dart';
import '../../features/profile/screens/loyalty_points_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/profile/screens/support_center_screen.dart';
import '../../features/profile/screens/wallet_screen.dart';
import '../providers/role_provider.dart';
import 'route_guard.dart';
import '../../features/rider/screens/rider_earnings_screen.dart';
import '../../features/rider/screens/rider_history_screen.dart';
import '../../features/rider/screens/rider_screen.dart';

/// Where the app opens for a given session.
///
/// A signed-in user starts on the panel their `profiles.role` row selects, so
/// a rider never lands in the customer app. Exposed as a function rather than
/// inlined so the rule is checkable on its own.
String initialLocationForSession({
  required bool isAuthenticated,
  required UserRole role,
}) =>
    isAuthenticated ? landingLocationForRole(role) : loginLocation;

/// Auth- and role-driven router. Navigation from login, post-signup redirect,
/// and token-expiry sign-out all flow through this one place instead of
/// per-screen checks.
///
/// The starting location is the panel the `profiles.role` column selects, and
/// [resolveAuthorizedLocation] re-checks the live session on every navigation
/// so a rider cannot be shown the customer panel, or vice versa.
final routerProvider = Provider<GoRouter>((ref) {
  final isAuthenticated = ref.watch(
    authStateProvider.select((s) => s.isAuthenticated && !s.isLoading),
  );
  final role = ref.watch(roleProvider).value ?? UserRole.customer;

  final router = GoRouter(
    initialLocation: initialLocationForSession(
      isAuthenticated: isAuthenticated,
      role: role,
    ),
    redirect: (context, state) {
      // Read live values rather than the captured ones: the router can outlive
      // a provider change, and the guard must reflect the current session.
      final auth = ref.read(authStateProvider);
      return resolveAuthorizedLocation(
        isAuthenticated: auth.isAuthenticated && !auth.isLoading,
        role: ref.read(roleProvider).value ?? UserRole.customer,
        requestedLocation: state.matchedLocation,
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
        path: customerLandingLocation,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/menu',
        builder: (context, state) => const MenuScreen(),
      ),
      GoRoute(
        path: '/orders/track',
        builder: (context, state) => const OrderTrackingScreen(),
      ),
      GoRoute(
        path: '/my-orders',
        builder: (context, state) => const MyOrdersScreen(),
      ),
      GoRoute(
        path: '/wallet',
        builder: (context, state) => const WalletScreen(),
      ),
      GoRoute(
        path: '/loyalty',
        builder: (context, state) => const LoyaltyPointsScreen(),
      ),
      GoRoute(
        path: '/addresses',
        builder: (context, state) => const AddressesScreen(),
      ),
      GoRoute(
        path: '/favorites',
        builder: (context, state) => const FavoritesScreen(),
      ),
      GoRoute(
        path: '/support',
        builder: (context, state) => const SupportCenterScreen(),
      ),
      GoRoute(
        path: '/delete-account',
        builder: (context, state) => const AccountDeletionScreen(),
      ),
      GoRoute(
        path: '/checkout',
        builder: (context, state) => const CheckoutScreen(),
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
        path: riderEarningsLocation,
        builder: (context, state) => const RiderEarningsScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});
