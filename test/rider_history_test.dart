import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/app_theme.dart';
import 'package:mrpizza/features/rider/data/rider_repository.dart';
import 'package:mrpizza/features/rider/models/rider_delivery.dart';
import 'package:mrpizza/features/rider/providers/rider_providers.dart';
import 'package:mrpizza/features/rider/screens/rider_history_screen.dart';

class _FakeRiderRepository extends RiderRepository {
  _FakeRiderRepository({this.deliveries = const []});

  final List<RiderDelivery> deliveries;
  int historyPageCalls = 0;

  @override
  Future<RiderDeliveryPage> fetchDeliveryHistoryPage({
    required int limit,
    required int offset,
  }) async {
    historyPageCalls++;
    final ended = deliveries.where((d) => !d.isOffer && !d.isActive).toList();
    final page = ended.skip(offset).take(limit).toList();
    return RiderDeliveryPage(
      deliveries: page,
      hasMore: offset + page.length < ended.length,
    );
  }
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
    await tester
        .pumpWidget(_app(_FakeRiderRepository(), const RiderHistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('No completed deliveries'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the first page is capped and load more appends the rest', () async {
    final repository = _FakeRiderRepository(deliveries: [
      for (var i = 0; i < 25; i++) _delivery(status: 'delivered', id: '$i'),
    ]);
    final container = ProviderContainer(
      overrides: [riderRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final first = await container.read(riderHistoryControllerProvider.future);
    expect(first.deliveries, hasLength(riderHistoryPageSize));
    expect(first.hasMore, isTrue);

    await container.read(riderHistoryControllerProvider.notifier).loadMore();
    final second = container.read(riderHistoryControllerProvider).requireValue;
    expect(second.deliveries, hasLength(25));
    expect(second.hasMore, isFalse);
    expect(second.isLoadingMore, isFalse);
    expect(repository.historyPageCalls, 2);
  });

  test('the first page already ends the list when it fits', () async {
    final repository = _FakeRiderRepository(deliveries: [
      _delivery(status: 'delivered', id: '1'),
      _delivery(status: 'failed', id: '2'),
    ]);
    final container = ProviderContainer(
      overrides: [riderRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final first = await container.read(riderHistoryControllerProvider.future);
    expect(first.deliveries, hasLength(2));
    expect(first.hasMore, isFalse);
  });
}
