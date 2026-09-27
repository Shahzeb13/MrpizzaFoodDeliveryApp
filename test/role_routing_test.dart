import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/role_provider.dart';
import 'package:mrpizza/core/routing/route_guard.dart';
import 'package:mrpizza/features/profile/data/profile_repository.dart';
import 'package:mrpizza/features/profile/models/profile.dart';
import 'package:mrpizza/features/profile/providers/profile_provider.dart';

/// Serves one fixed `profiles` row so the role can be resolved without Supabase.
class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository(this.row);

  final UserProfile? row;

  @override
  Future<UserProfile?> fetchProfile(String userId) async => row;
}

UserProfile _profileWithRole(String role) =>
    UserProfile(id: 'user-1', fullName: 'Test', phone: '0', role: role);

ProviderContainer _containerFor({required String? userId, required UserProfile? row}) {
  return ProviderContainer(
    overrides: [
      currentUserIdProvider.overrideWithValue(userId),
      profileRepositoryProvider.overrideWithValue(_FakeProfileRepository(row)),
    ],
  );
}

void main() {
  group('the raw profiles.role column maps to a role', () {
    test('rider stays a rider and lands on the rider panel', () {
      expect(userRoleFromDatabaseValue('rider'), UserRole.rider);
      expect(landingLocationForRole(UserRole.rider), riderLandingLocation);
    });

    test('customer stays a customer and lands on the customer panel', () {
      expect(userRoleFromDatabaseValue('customer'), UserRole.customer);
      expect(landingLocationForRole(UserRole.customer), customerLandingLocation);
    });

    test('surrounding whitespace and casing do not demote a rider', () {
      expect(userRoleFromDatabaseValue('Rider'), UserRole.rider);
      expect(userRoleFromDatabaseValue('  rider  '), UserRole.rider);
    });

    test('a missing or unrecognised value falls back to customer', () {
      expect(userRoleFromDatabaseValue(null), UserRole.customer);
      expect(userRoleFromDatabaseValue(''), UserRole.customer);
      expect(userRoleFromDatabaseValue('admin'), UserRole.customer);
    });
  });

  group('the signed-in role is read from the profiles table', () {
    test('a row marked rider resolves to the rider role', () async {
      final container = _containerFor(
        userId: 'rider-uuid',
        row: _profileWithRole('rider'),
      );
      addTearDown(container.dispose);

      expect(await container.read(roleProvider.future), UserRole.rider);
    });

    test('a row marked customer resolves to the customer role', () async {
      final container = _containerFor(
        userId: 'customer-uuid',
        row: _profileWithRole('customer'),
      );
      addTearDown(container.dispose);

      expect(await container.read(roleProvider.future), UserRole.customer);
    });

    test('a user with no profile row resolves to customer without throwing',
        () async {
      final container = _containerFor(userId: 'orphan-uuid', row: null);
      addTearDown(container.dispose);

      expect(await container.read(roleProvider.future), UserRole.customer);
    });

    test('a signed-out visitor resolves to customer without querying', () async {
      final container = _containerFor(userId: null, row: null);
      addTearDown(container.dispose);

      expect(await container.read(roleProvider.future), UserRole.customer);
    });
  });

  group('the route guard blocks the wrong panel', () {
    test('a signed-out visitor is sent to login from any app screen', () {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: false,
          role: UserRole.customer,
          requestedLocation: customerLandingLocation,
        ),
        loginLocation,
      );
    });

    test('a customer cannot open the rider panel', () {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.customer,
          requestedLocation: riderLandingLocation,
        ),
        customerLandingLocation,
      );
    });

    test('a rider can open the rider panel', () {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.rider,
          requestedLocation: riderLandingLocation,
        ),
        isNull,
      );
    });

    test('a rider is not locked out of the shared account screens', () {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.rider,
          requestedLocation: '/profile',
        ),
        isNull,
      );
    });

    test('a signed-in user is moved off the login screen to their own panel',
        () {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.rider,
          requestedLocation: loginLocation,
        ),
        riderLandingLocation,
      );
    });

    test('a signed-out visitor stays on the login screen', () {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: false,
          role: UserRole.customer,
          requestedLocation: loginLocation,
        ),
        isNull,
      );
    });
  });
}
