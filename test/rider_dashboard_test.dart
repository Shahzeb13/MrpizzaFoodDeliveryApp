import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/app_theme.dart';
import 'package:mrpizza/features/auth/data/auth_repository.dart';
import 'package:mrpizza/features/auth/providers/auth_provider.dart';
import 'package:mrpizza/features/rider/data/rider_repository.dart';
import 'package:mrpizza/features/rider/models/rider_delivery.dart';
import 'package:mrpizza/features/rider/screens/rider_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A signed-in session so [currentUserIdProvider] never touches the global
/// Supabase client, which is not initialised in a unit test.
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

class _FakeRiderRepository extends RiderRepository {
  _FakeRiderRepository({this.details, this.deliveries = const []});

  final RiderDetails? details;
  final List<RiderDelivery> deliveries;
  final List<String> called = [];

  @override
  Future<RiderDetails?> fetchRiderDetails() async => details;

  @override
  Stream<List<RiderDelivery>> streamDeliveries({
    Duration safetyNetPollInterval = riderSafetyNetPollInterval,
    Duration firstReadRetryDelay = riderFirstReadRetryDelay,
    int firstReadMaxAttempts = riderFirstReadMaxAttempts,
  }) =>
      Stream<List<RiderDelivery>>.value(deliveries);

  @override
  Future<List<RiderDelivery>> fetchDeliveries() async => deliveries;

  @override
  Future<void> claimOffer(String id) async => called.add('claim');
  @override
  Future<void> declineOffer(String id) async => called.add('decline');
  @override
  Future<void> markPickedUp(String id) async => called.add('pickup');
  @override
  Future<void> completeDelivery(String id) async => called.add('complete');
}

const _details = RiderDetails(
  branchId: 'b1',
  branchName: 'Abbottabad',
  branchAddress: 'Niazi Road',
);

RiderDelivery _delivery({
  String status = 'accepted',
  String id = 'a1',
  String? customerName = 'Usama Khan',
  String? customerPhone = '03001234567',
  String? deliveryAddress = 'Mandian, Abbottabad',
  double? latitude = 34.1688,
  double? longitude = 73.2215,
  String? deliveredAt,
}) =>
    RiderDelivery(
      assignmentId: id,
      orderId: 'o$id',
      billNumber: '#MP-84910',
      assignmentStatus: status,
      customerName: customerName ?? '',
      customerPhone: customerPhone ?? '',
      deliveryAddress: deliveryAddress ?? '',
      deliveryLatitude: latitude,
      deliveryLongitude: longitude,
      branchName: 'Abbottabad',
      branchAddress: 'Niazi Road',
      itemSummary: '2x Zinger, 1x Coke',
      itemCount: 3,
      assignedAt: DateTime(2026, 9, 28, 10),
      pickedUpAt: null,
      deliveredAt: deliveredAt == null ? null : DateTime.parse(deliveredAt),
    );

Widget _app(_FakeRiderRepository repository) => ProviderScope(
      overrides: [
        riderRepositoryProvider.overrideWithValue(repository),
        authStateProvider
            .overrideWith((ref) => AuthNotifier(_SignedInAuthRepository())),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const RiderScreen(),
      ),
    );

/// The auth notifier arms a 500ms startup safety-net timer, so the tree is
/// pumped past it or the test ends with a pending timer.
Future<void> _settle(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'a rider with no record is told to contact the branch, not shown a blank screen',
      (tester) async {
    await _settle(tester, _app(_FakeRiderRepository(details: null)));

    expect(find.textContaining('not set up'), findsOneWidget);
    expect(find.textContaining('No deliveries waiting'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an available rider with no work sees the empty state',
      (tester) async {
    await _settle(tester, _app(_FakeRiderRepository(details: _details)));

    expect(find.textContaining('No deliveries waiting'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pending offer shows accept and decline', (tester) async {
    await _settle(
        tester,
        _app(_FakeRiderRepository(
          details: _details,
          deliveries: [_delivery(status: 'assigned')],
        )));

    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an accepted job shows the customer, address and pickup button',
      (tester) async {
    await _settle(
        tester,
        _app(_FakeRiderRepository(
          details: _details,
          deliveries: [_delivery(status: 'accepted')],
        )));

    expect(find.text('Usama Khan'), findsOneWidget);
    expect(find.text('Mandian, Abbottabad'), findsOneWidget);
    expect(find.text("I've Picked Up"), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Open in Maps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a picked up job offers completion, not pickup', (tester) async {
    await _settle(
        tester,
        _app(_FakeRiderRepository(
          details: _details,
          deliveries: [_delivery(status: 'picked_up')],
        )));

    expect(find.text('Mark Delivered'), findsOneWidget);
    expect(find.text("I've Picked Up"), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old order with no snapshot says so instead of showing blanks',
      (tester) async {
    await _settle(
        tester,
        _app(_FakeRiderRepository(
          details: _details,
          deliveries: [
            _delivery(
              status: 'accepted',
              customerName: null,
              customerPhone: null,
              deliveryAddress: null,
              latitude: null,
              longitude: null,
            )
          ],
        )));

    expect(find.textContaining('Contact details unavailable'), findsOneWidget);
    expect(find.text('Call'), findsNothing);
    expect(find.text('Open in Maps'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dashboard shows the completed count and no money figure',
      (tester) async {
    await _settle(
        tester,
        _app(_FakeRiderRepository(
          details: _details,
          deliveries: [
            _delivery(
                status: 'delivered',
                id: 'd1',
                deliveredAt: '2026-09-28T12:00:00Z')
          ],
        )));

    expect(find.text('1'), findsOneWidget);
    // Riders are paid a monthly salary by the branch, so the app must not
    // invent a per-delivery figure they were never shown.
    expect(find.textContaining('Earnings'), findsNothing);
    expect(find.textContaining('payout'), findsNothing);
    expect(find.textContaining('Rs.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a recent delivery opens its order details when tapped',
      (tester) async {
    await _settle(
        tester,
        _app(_FakeRiderRepository(
          details: _details,
          deliveries: [
            _delivery(
                status: 'delivered',
                id: 'd1',
                deliveredAt: '2026-09-28T12:00:00Z')
          ],
        )));

    expect(find.text('Mandian, Abbottabad'), findsNothing);

    await tester.tap(find.text('#MP-84910'));
    await tester.pumpAndSettle();

    expect(find.text('Mandian, Abbottabad'), findsOneWidget);
    expect(find.text('2x Zinger, 1x Coke'), findsOneWidget);
    expect(find.text('Collect from Abbottabad'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no availability toggle is offered to the rider', (tester) async {
    await _settle(tester, _app(_FakeRiderRepository(details: _details)));

    expect(find.text('Go Online'), findsNothing);
    expect(find.text('Go Offline'), findsNothing);
    expect(find.textContaining('You are online'), findsNothing);
    expect(find.textContaining('You are offline'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed load offers a retry instead of a blank screen',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        riderRepositoryProvider
            .overrideWith((ref) => _ThrowingRiderRepository()),
        authStateProvider
            .overrideWith((ref) => AuthNotifier(_SignedInAuthRepository())),
      ],
    );
    addTearDown(container.dispose);

    await _settle(
      tester,
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const RiderScreen(),
        ),
      ),
    );

    expect(find.textContaining('Could not load'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

class _ThrowingRiderRepository extends RiderRepository {
  @override
  Future<RiderDetails?> fetchRiderDetails() async {
    throw const RiderRepositoryException('network down');
  }
}
