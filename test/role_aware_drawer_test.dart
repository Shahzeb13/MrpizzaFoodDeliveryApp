import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/role_provider.dart';
import 'package:mrpizza/features/auth/data/auth_repository.dart';
import 'package:mrpizza/features/auth/providers/auth_provider.dart';
import 'package:mrpizza/features/profile/providers/profile_provider.dart';
import 'package:mrpizza/widgets/app_drawer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A session that is already signed in, so the drawer header has an email
/// without any Supabase round trip.
class _SignedInAuthRepository extends AuthRepository {
  @override
  Session? get currentSession => Session(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'bearer',
        user: const User(
          id: 'rider-uuid',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-09-28T10:00:00Z',
          email: 'rider@test.com',
        ),
      );

  @override
  Stream<AuthState> get onAuthStateChange => const Stream<AuthState>.empty();
}

class _FixedRole extends RoleNotifier {
  _FixedRole(this._role);

  final UserRole _role;

  @override
  Future<UserRole> build() async => _role;
}

Widget _app(UserRole role) => ProviderScope(
      overrides: [
        roleProvider.overrideWith(() => _FixedRole(role)),
        authStateProvider
            .overrideWith((ref) => AuthNotifier(_SignedInAuthRepository())),
        // The drawer header reads the profile from the database; there is no
        // Supabase in a unit test.
        profileFutureProvider.overrideWith((ref) async => null),
      ],
      child: const MaterialApp(home: Scaffold(body: AppDrawer())),
    );

/// Drawer tiles are read after Riverpod and the auth notifier have settled.
/// The auth notifier arms a 500ms startup safety-net timer in its constructor,
/// so the tree is pumped past it or the test ends with a pending timer.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpWidget(_currentApp!);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

Widget? _currentApp;

void main() {
  testWidgets('a rider sees deliveries, earnings and support', (tester) async {
    _currentApp = _app(UserRole.rider);
    await _settle(tester);

    expect(find.text('My Deliveries'), findsOneWidget);
    expect(find.text('My Earnings'), findsOneWidget);
    expect(find.text('Support Center'), findsOneWidget);
    expect(find.text('Loyalty Points'), findsNothing);
    expect(find.text('My Addresses'), findsNothing);
    expect(find.text('My Favourites'), findsNothing);
    expect(find.text('Req Account Deletion'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a customer keeps the customer tiles', (tester) async {
    _currentApp = _app(UserRole.customer);
    await _settle(tester);

    expect(find.text('Loyalty Points'), findsOneWidget);
    expect(find.text('My Addresses'), findsOneWidget);
    expect(find.text('My Favourites'), findsOneWidget);
    expect(find.text('My Orders'), findsOneWidget);
    expect(find.text('Support Center'), findsOneWidget);
    expect(find.text('My Deliveries'), findsNothing);
    expect(find.text('My Earnings'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logout is offered to both roles', (tester) async {
    for (final role in UserRole.values) {
      _currentApp = _app(role);
      await _settle(tester);
      expect(find.text('Logout'), findsOneWidget,
          reason: 'a $role should be able to log out');
    }
  });
}
