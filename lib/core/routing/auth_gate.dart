import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../theme/app_theme.dart';
import 'router.dart';

/// Root gate that owns startup session handling and auth-driven routing.
///
/// While the initial `currentSession` check runs it shows [SplashScreen] so an
/// already-logged-in user never sees a flash of the login screen. After that it
/// delegates navigation to [routerProvider], which rebuilds whenever the auth
/// state flips (signedIn -> home, signedOut -> login) — one single source of
/// truth, no per-screen auth checks.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    if (authState.isInitializing) {
      return const SplashScreen();
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
