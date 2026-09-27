import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/role_provider.dart';
import 'package:mrpizza/core/routing/auth_gate.dart';
import 'package:mrpizza/core/routing/route_guard.dart';
import 'package:mrpizza/core/routing/router.dart';
import 'package:mrpizza/features/auth/data/auth_repository.dart';
import 'package:mrpizza/features/auth/providers/auth_provider.dart';
import 'package:mrpizza/features/auth/screens/splash_screen.dart';
import 'package:mrpizza/features/home/screens/home_screen.dart';
import 'package:mrpizza/features/profile/data/profile_repository.dart';
import 'package:mrpizza/features/profile/models/profile.dart';
import 'package:mrpizza/features/profile/providers/profile_provider.dart';
import 'package:mrpizza/features/rider/screens/rider_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _riderUserId = '75944721-332f-4136-94f1-6715c5964e0f';

Session _sessionFor(String userId) => Session(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      tokenType: 'bearer',
      user: User(
        id: userId,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-09-27T10:18:21Z',
        email: 'rider@test.com',
      ),
    );

/// A session that is already signed in, so the app boots the way a rider's does
/// when they reopen the app rather than tapping the login button.
class _SignedInAuthRepository extends AuthRepository {
  _SignedInAuthRepository(this._session);

  final Session _session;

  @override
  Session? get currentSession => _session;

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async =>
      AuthResponse(session: _session);

  @override
  Stream<AuthState> get onAuthStateChange => Stream<AuthState>.value(
        AuthState(AuthChangeEvent.initialSession, _session),
      );
}

/// Serves one `profiles` row, or never answers at all when [row] is left as a
/// pending future — that is the state the app is briefly in after sign-in.
class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository(this.pendingRow);

  final Future<UserProfile?> pendingRow;

  @override
  Future<UserProfile?> fetchProfile(String userId) => pendingRow;
}

UserProfile _riderRow() => const UserProfile(
      id: _riderUserId,
      fullName: 'Test Rider',
      phone: '0',
      role: 'rider',
    );

void main() {
  group('the panel a user lands on comes from their profiles.role row', () {
    test('a rider account starts on the rider panel', () async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => AuthNotifier(
                _SignedInAuthRepository(_sessionFor(_riderUserId))),
          ),
          profileRepositoryProvider.overrideWithValue(
            _FakeProfileRepository(Future.value(_riderRow())),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(authStateProvider.notifier)
          .login('rider@test.com', 'password');

      final role = await container.read(roleProvider.future);

      expect(role, UserRole.rider);
      expect(
        initialLocationForSession(isAuthenticated: true, role: role),
        riderLandingLocation,
      );
    });

    test('a customer account starts on the customer panel', () async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => AuthNotifier(
                _SignedInAuthRepository(_sessionFor(_riderUserId))),
          ),
          profileRepositoryProvider.overrideWithValue(
            _FakeProfileRepository(
              Future.value(
                const UserProfile(
                  id: _riderUserId,
                  fullName: 'Test Customer',
                  phone: '0',
                  role: 'customer',
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(authStateProvider.notifier)
          .login('customer@test.com', 'password');

      final role = await container.read(roleProvider.future);

      expect(role, UserRole.customer);
      expect(
        initialLocationForSession(isAuthenticated: true, role: role),
        customerLandingLocation,
      );
    });

    test('a signed-out visitor starts on the login screen', () {
      expect(
        initialLocationForSession(
          isAuthenticated: false,
          role: UserRole.customer,
        ),
        loginLocation,
      );
    });
  });

  testWidgets(
      'no panel is shown while the role is still being read from the database',
      (tester) async {
    // The sign-in moment: the session is already live, but the `profiles` row
    // has not come back yet. Building the router here is what sent riders to
    // the customer panel, because the only role available was a default.
    final neverAnswers = Completer<UserProfile?>();
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => AuthNotifier(
              _SignedInAuthRepository(_sessionFor(_riderUserId))),
        ),
        profileRepositoryProvider.overrideWithValue(
          _FakeProfileRepository(neverAnswers.future),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AuthGate(),
      ),
    );
    // Past the auth notifier's startup safety-net delay, so the session is
    // definitely applied and the splash can only be held by the role.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(container.read(authStateProvider).isAuthenticated, isTrue);
    // The role read is genuinely in flight, so the splash below is held by the
    // role and not by the session still being restored.
    expect(container.read(roleProvider).isLoading, isTrue);
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(RiderScreen), findsNothing);

    neverAnswers.complete(_riderRow());
  });
}
