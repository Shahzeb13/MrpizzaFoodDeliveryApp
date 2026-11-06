import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/role_provider.dart';
import 'package:mrpizza/core/routing/route_guard.dart';

/// The screens a guest is meant to browse, and the ones that stay gated,
/// used as lists so a change to the public set cannot quietly empty one side.
const guestBrowsableScreens = [
  customerLandingLocation,
  menuLocation,
  profileLocation,
  supportCenterLocation,
  '/support/document/termsAndConditions',
];

const loginGatedScreens = [
  checkoutLocation,
  applyDiscountLocation,
  paymentMethodLocation,
  trackOrderLocation,
  myOrdersLocation,
  addressesLocation,
  walletLocation,
  loyaltyLocation,
  favoritesLocation,
  deleteAccountLocation,
];

String loginWithReturn(String location) =>
    '$loginLocation?return=${Uri.encodeComponent(location)}';

void main() {
  group('signed-out browsing', () {
    test('the store front is open without an account', () {
      for (final location in guestBrowsableScreens) {
        expect(
          resolveAuthorizedLocation(
            isAuthenticated: false,
            role: UserRole.customer,
            requestedLocation: location,
          ),
          isNull,
          reason: '$location should be browsable signed out',
        );
      }
    });

    test('checkout and the account screens still need a session, and carry '
        'their own return target', () {
      for (final location in loginGatedScreens) {
        expect(
          resolveAuthorizedLocation(
            isAuthenticated: false,
            role: UserRole.customer,
            requestedLocation: location,
          ),
          loginWithReturn(location),
          reason: '$location should redirect to login with a return target',
        );
      }
    });

    test('an unknown location fails closed to login', () {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: false,
          role: UserRole.customer,
          requestedLocation: '/admin/secret-panel',
        ),
        loginWithReturn('/admin/secret-panel'),
      );
    });
  });

  group('resuming an interrupted checkout after login', () {
    test('a signed-in customer holding a return target goes straight back '
        'to it instead of the menu', () {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.customer,
          requestedLocation: loginLocation,
          returnTarget: checkoutLocation,
        ),
        checkoutLocation,
      );
    });

    test('a signed-in customer without a return target lands on their panel',
        () {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.customer,
          requestedLocation: loginLocation,
        ),
        customerLandingLocation,
      );
    });

    test('a return target the app does not have a route for is ignored', () {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.customer,
          requestedLocation: loginLocation,
          returnTarget: 'https://evil.example.com',
        ),
        customerLandingLocation,
      );
    });

    test('a rider finishing a checkout-shaped login goes to the rider panel, '
        'not customer checkout', () {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.rider,
          requestedLocation: loginLocation,
          returnTarget: checkoutLocation,
        ),
        riderLandingLocation,
      );
    });

    test('a customer deep-linking checkout after login is allowed through',
        () {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.customer,
          requestedLocation: checkoutLocation,
        ),
        isNull,
      );
    });
  });

  group('role guards while the role is still loading', () {
    test('navigation is suspended rather than guessed at', () {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.customer,
          isRoleLoading: true,
          requestedLocation: loginLocation,
          returnTarget: checkoutLocation,
        ),
        isNull,
        reason: 'A rider may be waiting on this answer; stay put.',
      );
    });

    test('a signed-out visitor is never suspended by a role nobody is '
        'fetching', () {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: false,
          role: UserRole.customer,
          isRoleLoading: true,
          requestedLocation: checkoutLocation,
        ),
        loginWithReturn(checkoutLocation),
      );
    });
  });

  group('rider protections over the customer commerce screens', () {
    test('customer commerce screens bounce a rider to their panel', () {
      for (final location in customerOnlyLocations) {
        expect(
          resolveAuthorizedLocation(
            isAuthenticated: true,
            role: UserRole.rider,
            requestedLocation: location,
          ),
          riderLandingLocation,
          reason: '$location is a customer screen',
        );
      }
    });

    test('the customer storefront is closed to a signed-in rider', () {
      for (final location in customerStorefrontLocations) {
        expect(
          resolveAuthorizedLocation(
            isAuthenticated: true,
            role: UserRole.rider,
            requestedLocation: location,
          ),
          riderLandingLocation,
          reason: '$location builds the customer panel a rider does not have',
        );
      }
    });

    test('a rider handed the storefront back as a resume target lands on '
        'their panel instead', () {
      for (final location in customerStorefrontLocations) {
        expect(
          resolveAuthorizedLocation(
            isAuthenticated: true,
            role: UserRole.rider,
            requestedLocation: loginLocation,
            returnTarget: location,
          ),
          riderLandingLocation,
          reason: '$location is not a place for a rider to resume from',
        );
      }
    });

    test('riders keep the shared account screens', () {
      for (final location in [profileLocation, myOrdersLocation]) {
        expect(
          resolveAuthorizedLocation(
            isAuthenticated: true,
            role: UserRole.rider,
            requestedLocation: location,
          ),
          isNull,
          reason: '$location belongs to both roles',
        );
      }
    });
  });

  group('the resume target round-trips through the login screen', () {
    test('the resume target survives a login<->signup round trip', () {
      final carried = Uri.parse('$signupLocation?return=%2Fcheckout')
          .queryParameters['return'];
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.customer,
          requestedLocation: signupLocation,
          returnTarget: carried,
        ),
        checkoutLocation,
      );
    });

    test('the signed-out bounce round-trips through its own query encoding',
        () {
      final bounced = resolveAuthorizedLocation(
        isAuthenticated: false,
        role: UserRole.customer,
        requestedLocation: checkoutLocation,
      );
      final parsed = Uri.parse(bounced!);
      expect(parsed.path, loginLocation);
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.customer,
          requestedLocation: loginLocation,
          returnTarget: parsed.queryParameters['return'],
        ),
        checkoutLocation,
      );
    });
  });
}
