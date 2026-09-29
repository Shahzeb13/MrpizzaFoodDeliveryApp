import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/app_theme.dart';
import 'package:mrpizza/features/rider/data/rider_repository.dart';
import 'package:mrpizza/features/rider/models/rider_availability.dart';
import 'package:mrpizza/features/rider/models/rider_delivery.dart';
import 'package:mrpizza/features/rider/screens/rider_screen.dart';

class _FakeRiderRepository extends RiderRepository {
  _FakeRiderRepository({this.details, this.deliveries = const []});

  final RiderDetails? details;
  final List<RiderDelivery> deliveries;
  final List<String> called = [];

  @override
  Future<RiderDetails?> fetchRiderDetails() async => details;

  @override
  Stream<List<RiderDelivery>> streamDeliveries() =>
      Stream<List<RiderDelivery>>.value(deliveries);

  @override
  Future<List<RiderDelivery>> fetchDeliveries() async => deliveries;

  @override
  Future<double> fetchPayoutRate() async => 250;

  @override
  Future<void> setAvailability(String status) async =>
      called.add('availability:$status');
  @override
  Future<void> claimOffer(String id) async => called.add('claim');
  @override
  Future<void> declineOffer(String id) async => called.add('decline');
  @override
  Future<void> markPickedUp(String id) async => called.add('pickup');
  @override
  Future<void> completeDelivery(String id) async => called.add('complete');
}

RiderDetails _details(RiderAvailability availability) => RiderDetails(
      branchId: 'b1',
      availability: availability,
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
      overrides: [riderRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const RiderScreen(),
      ),
    );

void main() {
  testWidgets(
      'a rider with no record is told to contact the branch, not shown a blank screen',
      (tester) async {
    await tester.pumpWidget(_app(_FakeRiderRepository(details: null)));
    await tester.pumpAndSettle();

    expect(find.textContaining('not set up'), findsOneWidget);
    expect(find.textContaining('No deliveries waiting'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an available rider with no work sees the empty state',
      (tester) async {
    await tester.pumpWidget(
        _app(_FakeRiderRepository(details: _details(RiderAvailability.available))));
    await tester.pumpAndSettle();

    expect(find.textContaining('No deliveries waiting'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pending offer shows accept and decline', (tester) async {
    await tester.pumpWidget(_app(_FakeRiderRepository(
      details: _details(RiderAvailability.available),
      deliveries: [_delivery(status: 'assigned')],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an accepted job shows the customer, address and pickup button',
      (tester) async {
    await tester.pumpWidget(_app(_FakeRiderRepository(
      details: _details(RiderAvailability.onDelivery),
      deliveries: [_delivery(status: 'accepted')],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Usama Khan'), findsOneWidget);
    expect(find.text('Mandian, Abbottabad'), findsOneWidget);
    expect(find.text("I've Picked Up"), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Open in Maps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a picked up job offers completion, not pickup', (tester) async {
    await tester.pumpWidget(_app(_FakeRiderRepository(
      details: _details(RiderAvailability.onDelivery),
      deliveries: [_delivery(status: 'picked_up')],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Mark Delivered'), findsOneWidget);
    expect(find.text("I've Picked Up"), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old order with no snapshot says so instead of showing blanks',
      (tester) async {
    await tester.pumpWidget(_app(_FakeRiderRepository(
      details: _details(RiderAvailability.onDelivery),
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
    await tester.pumpAndSettle();

    expect(find.textContaining('Contact details unavailable'), findsOneWidget);
    expect(find.text('Call'), findsNothing);
    expect(find.text('Open in Maps'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('today shows the completed count and the configured payout',
      (tester) async {
    await tester.pumpWidget(_app(_FakeRiderRepository(
      details: _details(RiderAvailability.available),
      deliveries: [
        _delivery(status: 'delivered', id: 'd1', deliveredAt: '2026-09-28T12:00:00Z')
      ],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Rs. 250'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('going offline is offered to an available rider', (tester) async {
    final repository = _FakeRiderRepository(
      details: _details(RiderAvailability.available),
    );
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Go Offline'));
    await tester.pumpAndSettle();

    expect(repository.called, contains('availability:offline'));
  });

  testWidgets('a failed load offers a retry instead of a blank screen',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        riderRepositoryProvider.overrideWith((ref) => _ThrowingRiderRepository()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const RiderScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

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
