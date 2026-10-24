import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/role_provider.dart';
import 'package:mrpizza/features/auth/data/auth_repository.dart';
import 'package:mrpizza/features/auth/providers/auth_provider.dart';
import 'package:mrpizza/features/loyalty/models/loyalty.dart';
import 'package:mrpizza/features/loyalty/providers/loyalty_provider.dart';
import 'package:mrpizza/features/profile/providers/profile_provider.dart';
import 'package:mrpizza/widgets/app_drawer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The drawer tile used to read `trailing: _buildBadge('120 Points')` — a
/// literal, on every install, for every customer, including those who have never
/// ordered. These cases pin it to the ledger balance so it cannot drift back.
class _SignedInAuthRepository extends AuthRepository {
  @override
  Session? get currentSession => Session(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        tokenType: 'bearer',
        user: const User(
          id: 'customer-uuid',
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: '2026-09-28T10:00:00Z',
          email: 'customer@test.com',
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

/// Serves a fixed balance so the drawer never touches Supabase.
class _FixedBalance extends LoyaltyBalanceNotifier {
  _FixedBalance(this.value);

  final LoyaltyBalance value;

  @override
  Future<LoyaltyBalance> build() async => value;
}

LoyaltyBalance _balance(int points) => LoyaltyBalance(
      isSignedIn: true,
      balance: points,
      history: const [],
      settings: const LoyaltySettings(
        enabled: true,
        rupeesPerPoint: 10,
        redemptionValue: 1,
      ),
    );

Widget _app({required int points, required bool isSignedIn}) {
  return ProviderScope(
    overrides: [
      roleProvider.overrideWith(() => _FixedRole(UserRole.customer)),
      authStateProvider
          .overrideWith((ref) => AuthNotifier(_SignedInAuthRepository())),
      profileFutureProvider.overrideWith((ref) async => null),
      currentUserIdProvider.overrideWithValue('customer-uuid'),
      loyaltyBalanceProvider.overrideWith(
        () => _FixedBalance(
          isSignedIn ? _balance(points) : LoyaltyBalance.signedOut,
        ),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: AppDrawer())),
  );
}

/// The auth notifier arms a 500ms startup safety-net timer, so the tree is
/// pumped past it or the test ends with a pending timer.
Future<void> _settle(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

void main() {
  group('the loyalty badge shows the real balance', () {
    testWidgets('reads 2,257 points from the ledger', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _settle(tester, _app(points: 2257, isSignedIn: true));

      expect(find.text('2,257 Points'), findsOneWidget);
      // The old literal, which must never appear again.
      expect(find.text('120 Points'), findsNothing);
    });

    testWidgets('groups a four-figure balance', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _settle(tester, _app(points: 1234567, isSignedIn: true));

      expect(find.text('1,234,567 Points'), findsOneWidget);
    });

    testWidgets('shows a customer with no points a real zero', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _settle(tester, _app(points: 0, isSignedIn: true));

      expect(find.text('0 Points'), findsOneWidget);
      expect(find.text('120 Points'), findsNothing);
    });

    testWidgets('shows no badge at all when signed out', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _settle(tester, _app(points: 0, isSignedIn: false));

      // The tile is still there to tap — only the unverified figure is withheld.
      expect(find.text('Loyalty Points'), findsOneWidget);
      // Matched by shape, not by substring: the tile title itself ends in
      // "Points", so only a `<number> Points` badge counts as a badge.
      expect(
        find.textContaining(RegExp(r'^\d[\d,]*\s+Points$')),
        findsNothing,
      );
    });
  });
}