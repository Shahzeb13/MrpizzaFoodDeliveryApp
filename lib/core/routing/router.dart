import 'package:go_router/go_router.dart';

import '../../features/auth/screens/role_select_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/menu/screens/menu_screen.dart';
import '../../features/orders/screens/order_tracking_screen.dart';
import '../../features/payment/screens/checkout_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/rider/screens/rider_screen.dart';

/// App router.
///
/// Simple placeholders routes for this stage. Redirects / to the chosen
/// feature based on role will be added with real auth later.
final GoRouter router = GoRouter(
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const RoleSelectScreen(),
    ),
    GoRoute(
      path: '/home',
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
      path: '/checkout',
      builder: (context, state) => const CheckoutScreen(),
    ),
    GoRoute(
      path: '/rider',
      builder: (context, state) => const RiderScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
  ],
  initialLocation: '/login',
);