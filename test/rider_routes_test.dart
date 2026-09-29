import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/role_provider.dart';
import 'package:mrpizza/core/routing/route_guard.dart';

const _riderScreens = [
  riderHistoryLocation,
  riderEarningsLocation,
  riderLandingLocation,
];

void main() {
  test('a customer is kept out of every rider screen', () {
    for (final location in _riderScreens) {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.customer,
          requestedLocation: location,
        ),
        customerLandingLocation,
        reason: '$location should be closed to customers',
      );
    }
  });

  test('a rider may open every rider screen', () {
    for (final location in _riderScreens) {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.rider,
          requestedLocation: location,
        ),
        isNull,
        reason: '$location should be open to riders',
      );
    }
  });

  test('a signed out visitor is sent to login from every rider screen', () {
    for (final location in _riderScreens) {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: false,
          role: UserRole.customer,
          requestedLocation: location,
        ),
        loginLocation,
      );
    }
  });

  test('the shared account screens stay open to both roles', () {
    for (final location in ['/profile', '/wallet', '/support', '/my-orders']) {
      for (final role in [UserRole.customer, UserRole.rider]) {
        expect(
          resolveAuthorizedLocation(
            isAuthenticated: true,
            role: role,
            requestedLocation: location,
          ),
          isNull,
          reason: '$location should be open to a $role',
        );
      }
    }
  });
}
