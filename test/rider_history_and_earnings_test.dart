import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/app_theme.dart';
import 'package:mrpizza/features/rider/data/rider_repository.dart';
import 'package:mrpizza/features/rider/models/rider_availability.dart';
import 'package:mrpizza/features/rider/models/rider_delivery.dart';
import 'package:mrpizza/features/rider/screens/rider_earnings_screen.dart';
import 'package:mrpizza/features/rider/screens/rider_history_screen.dart';

class _FakeRiderRepository extends RiderRepository {
  _FakeRiderRepository({this.deliveries = const [], this.payoutRate = 250});

  final List<RiderDelivery> deliveries;
  final double payoutRate;

  @override
  Future<RiderDetails?> fetchRiderDetails() async => const RiderDetails(
        branchId: 'b1',
        availability: RiderAvailability.available,
        branchName: 'Abbottabad',
        branchAddress: 'Niazi Road',
      );

  @override
  Future<List<RiderDelivery>> fetchDeliveries() async => deliveries;

  @override
  Future<double> fetchPayoutRate() async => payoutRate;
}

RiderDelivery _delivery({
  required String status,
  String id = 'a',
  String? deliveredAt,
}) =>
    RiderDelivery(
      assignmentId: id,
      orderId: 'o$id',
      billNumber: '#$id',
      assignmentStatus: status,
      customerName: 'Usama',
      customerPhone: '0300',
      deliveryAddress: 'Mandian',
      deliveryLatitude: 34.16,
      deliveryLongitude: 73.22,
      branchName: 'Abbottabad',
      branchAddress: 'Niazi Road',
      itemSummary: '1x Zinger',
      itemCount: 1,
      assignedAt: DateTime(2026, 9, 28, 10),
      pickedUpAt: null,
      deliveredAt: deliveredAt == null ? null : DateTime.parse(deliveredAt),
    );

Widget _app(_FakeRiderRepository repository, Widget child) => ProviderScope(
      overrides: [riderRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(theme: AppTheme.light, home: child),
    );

void main() {
  testWidgets('history lists finished deliveries and hides active ones',
      (tester) async {
    await tester.pumpWidget(_app(
      _FakeRiderRepository(deliveries: [
        _delivery(
            status: 'delivered',
            id: 'done',
            deliveredAt: '2026-09-28T15:00:00Z'),
        _delivery(status: 'declined', id: 'no'),
        _delivery(status: 'accepted', id: 'live'),
      ]),
      const RiderHistoryScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('#done'), findsOneWidget);
    expect(find.text('#no'), findsOneWidget);
    expect(find.text('#live'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history says so when there is nothing yet', (tester) async {
    await tester.pumpWidget(
        _app(_FakeRiderRepository(), const RiderHistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('No completed deliveries'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('earnings shows the completed count times the configured rate',
      (tester) async {
    await tester.pumpWidget(_app(
      _FakeRiderRepository(
        deliveries: [
          _delivery(status: 'delivered', id: '1', deliveredAt: '2026-09-28T12:00:00Z'),
          _delivery(status: 'delivered', id: '2', deliveredAt: '2026-09-27T12:00:00Z'),
          _delivery(status: 'accepted', id: '3'),
        ],
      ),
      const RiderEarningsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Rs. 500'), findsOneWidget);
    expect(find.textContaining('Rs. 250 per delivery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('earnings says the rate is unavailable instead of showing zero',
      (tester) async {
    await tester.pumpWidget(_app(
      _FakeRiderRepository(
        deliveries: [
          _delivery(status: 'delivered', id: '1', deliveredAt: '2026-09-28T12:00:00Z')
        ],
        payoutRate: 0,
      ),
      const RiderEarningsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('rate is unavailable'), findsOneWidget);
    expect(find.text('Rs. 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('earnings with no deliveries still shows the rate',
      (tester) async {
    await tester.pumpWidget(
        _app(_FakeRiderRepository(), const RiderEarningsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Rs. 0'), findsOneWidget);
    expect(find.textContaining('rate is unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
