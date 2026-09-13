import 'package:go_router/go_router.dart';

import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/role_select_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
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
import '../../features/rider/screens/rider_screen.dart';

final GoRouter router = GoRouter(
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/signup',
      builder: (context, state) => const SignupScreen(),
    ),
    GoRoute(
      path: '/role_select',
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
      path: '/rider',
      builder: (context, state) => const RiderScreen(),
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
  ],
  initialLocation: '/splash',
);