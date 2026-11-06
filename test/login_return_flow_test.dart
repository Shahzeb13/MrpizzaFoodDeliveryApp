// Reproduction tests for the device report: guest taps Checkout, the router
// guard sends them to /login?return=/checkout, they sign in — and instead of
// resuming checkout the app stays on the login screen until they tap the
// close button.
//
// The harness runs the real routerProvider (real go_router, real redirect)
// with only the network-touching repositories faked, so the auth-flip ->
// refresh() -> redirect chain is exercised exactly as on a live device.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mrpizza/core/providers/role_provider.dart';
import 'package:mrpizza/core/routing/router.dart';
import 'package:mrpizza/core/theme/neumorphic.dart';
import 'package:mrpizza/features/auth/data/auth_repository.dart';
import 'package:mrpizza/features/auth/providers/auth_provider.dart';
import 'package:mrpizza/features/menu/data/menu_catalog.dart';
import 'package:mrpizza/features/menu/data/menu_repository.dart';
import 'package:mrpizza/features/menu/models/menu_item.dart';
import 'package:mrpizza/features/menu/providers/menu_provider.dart';
import 'package:mrpizza/features/payment/screens/checkout_screen.dart';
import 'package:mrpizza/features/profile/data/profile_repository.dart';
import 'package:mrpizza/features/profile/models/profile.dart';
import 'package:mrpizza/features/profile/providers/profile_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeAuthRepository extends AuthRepository {
  /// [queuedEvents] are buffered and delivered to the first listener, which
  /// is how "was already signed in before this run" is simulated.
  FakeAuthRepository({List<AuthState> queuedEvents = const []}) {
    for (final event in queuedEvents) {
      _events.add(event);
    }
  }

  /* Single-subscription: events queued before the listener attaches are
   * kept and delivered in full. */
  final _events = StreamController<AuthState>();

  @override
  Stream<AuthState> get onAuthStateChange => _events.stream;

  @override
  Session? get currentSession => null;

  @override
  User? get currentUser => null;

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    /* Realistic: the session carries a user, so the role provider really
     * rebuilds from null (signed out) to a user id exactly as on device.
     * Its profile read is served by FakeProfileRepository. */
    return AuthResponse(user: User.fromJson(const {'id': 'u1'}));
  }

  @override
  Future<void> signOut() async => _events.add(
        const AuthState(AuthChangeEvent.signedOut, null),
      );
}

class FakeMenuRepository extends MenuRepository {
  @override
  Future<MenuCatalog> fetchMenuCatalog() async => MenuCatalog.empty;

  @override
  Future<Map<String, MenuItem>> fetchAvailableItemsByIds(
    Set<String> ids,
  ) async =>
      const {};
}

class FakeProfileRepository extends ProfileRepository {
  FakeProfileRepository({this.profileFetchDelay});

  /// Lets a test hold the role read in flight, which is the condition the
  /// reported device stall happens under.
  final Duration? profileFetchDelay;

  @override
  Future<UserProfile?> fetchProfile(String userId) async {
    final delay = profileFetchDelay;
    if (delay != null) {
      await Future.delayed(delay);
    }
    return UserProfile(id: userId, fullName: '', phone: '');
  }

  @override
  Future<List<UserAddress>> fetchAddresses(String userId) async => const [];
}

class _RouterHarness extends ConsumerWidget {
  const _RouterHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(routerConfig: ref.watch(routerProvider));
  }
}

ProviderScope buildScope(
  FakeAuthRepository authRepository, {
  Duration? profileFetchDelay,
}) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith((ref) => AuthNotifier(authRepository)),
      profileRepositoryProvider.overrideWithValue(
        FakeProfileRepository(profileFetchDelay: profileFetchDelay),
      ),
      menuRepositoryProvider.overrideWithValue(FakeMenuRepository()),
    ],
    child: const _RouterHarness(),
  );
}

Future<GoRouter> pumpHarness(
  WidgetTester tester,
  FakeAuthRepository auth, {
  Duration? profileFetchDelay,
}) async {
  /* A real phone-sized viewport: at the tester's default 800x600 several
   * pre-existing Rows overflow and poison the test with layout exceptions
   * that have nothing to do with navigation. */
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(buildScope(auth, profileFetchDelay: profileFetchDelay));
  /* First pump settles the first frame, the second walks past the
   * AuthNotifier constructor's 500 ms startup safety timer so no pending
   * timer survives teardown. */
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
  return container.read(routerProvider);
}

Future<void> pumpThroughStartupWindow(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'guard resumes a guest to checkout after a successful sign-in',
    (tester) async {
      final auth = FakeAuthRepository();
      final router = await pumpHarness(tester, auth);

      /* Start on the store front as a guest. */
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/home',
      );

      /* What the device flow really runs: the guest taps Checkout and the
       * guard bounces it to the login screen carrying the return target.
       * (push() never updates the reported URL, so the screen on top is the
       * honest probe.) */
      router.push('/checkout');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.byType(CheckoutScreen), findsNothing);

      /* Fill the form first: the button rejects an empty form silently. */
      final emailFields = find.byType(TextFormField);
      await tester.enterText(emailFields.first, 'customer@example.com');
      await tester.enterText(emailFields.last, 'super-secret-password');
      await tester.pump();

      /* Sign in through the screen's own button, exactly as a customer does. */
      await tester.tap(
        find.ancestor(
          of: find.text('Sign in'),
          matching: find.byType(NeuPrimaryButton),
        ).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      /* The tap must have run the sign-in and the role must have landed:
       * the harness intercepts both, so a failure here means the flow
       * itself stopped working, not the routing. */
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      expect(
        container.read(authStateProvider).isAuthenticated,
        isTrue,
        reason: 'Tapping Sign in must complete the sign-in.',
      );
      expect(
        container.read(roleProvider).value,
        UserRole.customer,
      );

      /* THE BUG: the app is expected to land on checkout, not rest on the
       * login screen waiting for the close button. */
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(CheckoutScreen), findsOneWidget,
          reason: 'A successful sign-in carrying ?return=/checkout must '
              'resume the checkout immediately, without the user tapping '
              'the close button.');
      expect(find.text('Sign in'), findsNothing);

      await pumpThroughStartupWindow(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'already signed-in user opening /login?return=/checkout resumes it',
    (tester) async {
      final auth = FakeAuthRepository(
        queuedEvents: const [AuthState(AuthChangeEvent.signedIn, null)],
      );
      final router = await pumpHarness(tester, auth);

      router.go('/login?return=/checkout');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/checkout',
        reason: 'A signed-in user on /login?return=/checkout must be moved '
            'straight to checkout by the guard.',
      );

      await pumpThroughStartupWindow(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'resumes the moment sign-in lands, even while the role read is running',
    (tester) async {
      // The condition the real device showed: the credentials were accepted
      // and the app sat on the login screen while the role/profile read was
      // still doing its network round-trip. The resume must not depend on
      // that read finishing.
      final auth = FakeAuthRepository();
      final router = await pumpHarness(
        tester,
        auth,
        profileFetchDelay: const Duration(seconds: 30),
      );

      router.push('/checkout');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Sign in'), findsOneWidget);

      final emailFields = find.byType(TextFormField);
      await tester.enterText(emailFields.first, 'customer@example.com');
      await tester.enterText(emailFields.last, 'super-secret-password');
      await tester.pump();

      await tester.tap(
        find.ancestor(
          of: find.text('Sign in'),
          matching: find.byType(NeuPrimaryButton),
        ).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      /* The role read is still 28+ seconds away — and yet the checkout
       * must already be on screen. */
      /* Then the role read completes 30s later: its listener refresh runs on
       * the now-current /checkout and the guard confirms it — no bounce. */
      await tester.pump(const Duration(seconds: 31));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(CheckoutScreen), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
