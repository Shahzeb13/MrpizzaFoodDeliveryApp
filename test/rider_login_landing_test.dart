import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/role_provider.dart';
import 'package:mrpizza/core/routing/auth_gate.dart';
import 'package:mrpizza/features/auth/data/auth_repository.dart';
import 'package:mrpizza/features/auth/providers/auth_provider.dart';
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

/// Signed out until [signIn] is called, so the test can walk the real sequence:
/// the app boots with no session, the role provider answers "customer" because
/// there is no row to read, and only then does the rider tap Sign In.
class _StartsSignedOutRepository extends AuthRepository {
  _StartsSignedOutRepository(this._session);

  final Session _session;

  @override
  Session? get currentSession => null;

  @override
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async =>
      AuthResponse(session: _session);

  @override
  Stream<AuthState> get onAuthStateChange => const Stream<AuthState>.empty();
}

class _PendingProfileRepository extends ProfileRepository {
  _PendingProfileRepository(this.pendingRow);

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
  testWidgets('a rider who taps Sign In lands on the rider panel',
      (tester) async {
    final profileRow = Completer<UserProfile?>();
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => AuthNotifier(_StartsSignedOutRepository(_sessionFor(_riderUserId))),
        ),
        profileRepositoryProvider
            .overrideWithValue(_PendingProfileRepository(profileRow.future)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AuthGate()),
    );
    await tester.pump();

    // The app is on the login screen, and the role provider has already
    // answered "customer" because nobody is signed in yet. That stale answer is
    // what the router must not navigate on.
    expect(container.read(authStateProvider).isAuthenticated, isFalse);
    expect(container.read(roleProvider).hasValue, isTrue);
    expect(container.read(roleProvider).value, UserRole.customer);

    // Now the rider taps Sign In while the `profiles` row is still in flight.
    await container
        .read(authStateProvider.notifier)
        .login('rider@test.com', 'password');
    await tester.pump();

    expect(find.byType(HomeScreen), findsNothing);

    profileRow.complete(_riderRow());
    await tester.pumpAndSettle();

    expect(find.byType(RiderScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(container.read(roleProvider).value, UserRole.rider);
  });
}
