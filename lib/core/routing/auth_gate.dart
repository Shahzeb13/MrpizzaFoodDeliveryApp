import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../providers/role_provider.dart';
import '../theme/app_theme.dart';
import 'router.dart';

/// Root gate that owns startup session handling and auth-driven routing.
///
/// While the initial `currentSession` check runs it shows [SplashScreen] so an
/// already-logged-in user never sees a flash of the login screen. It also waits
/// for the role to be resolved from `profiles` before building the router:
/// navigation depends on that role, so mounting the router earlier would let it
/// commit to the customer panel on a stale default and then strand a rider
/// there once the real role arrived. After that it delegates navigation to
/// [routerProvider], which rebuilds whenever the auth state flips (signedIn ->
/// role landing, signedOut -> login) — one single source of truth, no
/// per-screen auth checks.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});
  //build\app\outputs\flutter-apk\app-debug.apk
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final roleState = ref.watch(roleProvider);

    // The role is only worth waiting for when there is a session to place. A
    // signed-out visitor resolves it instantly (there is no row to read), so
    // gating on it unconditionally would add a splash screen to every launch
    // for nothing. A failed role lookup reports an error rather than staying
    // loading, so this cannot deadlock the splash; the router then falls back
    // to customer.
    final isResolvingRole = authState.isAuthenticated && roleState.isLoading;

    if (authState.isInitializing || isResolvingRole) {
      // Splash is rendered before the router's MaterialApp exists, so give it
      // its own lightweight MaterialApp shell (Directionality/theme) here. It
      // is swapped for the real router once the session and role are known.
      return MaterialApp(
        title: 'MrPizza',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const SplashScreen(),
      );
    }

    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'MrPizza',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
