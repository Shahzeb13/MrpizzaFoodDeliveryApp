import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/rider/data/rider_repository.dart';
import 'package:mrpizza/features/rider/models/rider_availability.dart';
import 'package:mrpizza/features/rider/models/rider_delivery.dart';
import 'package:mrpizza/features/rider/providers/rider_providers.dart';

class _FakeRiderRepository extends RiderRepository {
  _FakeRiderRepository({
    this.details,
    this.deliveries = const [],
    this.payoutRate = 250,
    this.failWith,
  });

  final RiderDetails? details;
  final List<RiderDelivery> deliveries;
  final double payoutRate;
  final String? failWith;
  final List<String> called = [];

  @override
  Future<RiderDetails?> fetchRiderDetails() async => details;

  @override
  Stream<List<RiderDelivery>> streamDeliveries() =>
      Stream<List<RiderDelivery>>.value(deliveries);

  @override
  Future<List<RiderDelivery>> fetchDeliveries() async => deliveries;

  @override
  Future<double> fetchPayoutRate() async => payoutRate;

  @override
  Future<void> claimOffer(String id) async => called.add('claim');
  @override
  Future<void> declineOffer(String id) async => called.add('decline');
  @override
  Future<void> markPickedUp(String id) async => called.add('pickup');
  @override
  Future<void> completeDelivery(String id) async => called.add('complete');
  @override
  Future<void> failDelivery(String id, String reason) async =>
      called.add('fail');
  @override
  Future<void> setAvailability(String status) async {
    if (failWith != null) throw RiderRepositoryException(failWith!);
    called.add('availability:$status');
  }
}

const _setUp = RiderDetails(
  branchId: 'b1',
  availability: RiderAvailability.available,
  branchName: 'Abbottabad',
  branchAddress: 'Niazi Road',
);

RiderDelivery _delivery(String status) => RiderDelivery(
      assignmentId: 'a',
      orderId: 'o',
      billNumber: '#1',
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
      assignedAt: DateTime(2026, 9, 28),
      pickedUpAt: null,
      deliveredAt: null,
    );

ProviderContainer _container(_FakeRiderRepository repository) {
  final container = ProviderContainer(
    overrides: [riderRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a rider with no record is reported, not treated as set up', () async {
    final container = _container(_FakeRiderRepository(details: null));

    expect(await container.read(riderDetailsProvider.future), isNull);
  });

  test('availability is derived from the rider record', () async {
    final container = _container(_FakeRiderRepository(details: _setUp));

    expect(await container.read(riderAvailabilityProvider.future),
        RiderAvailability.available);
  });

  test('a missing record reads as offline, never available', () async {
    final container = _container(_FakeRiderRepository(details: null));

    expect(await container.read(riderAvailabilityProvider.future),
        RiderAvailability.offline);
  });

  test('earnings use the configured rate', () async {
    final container = _container(_FakeRiderRepository(
      details: _setUp,
      deliveries: [_delivery('delivered'), _delivery('accepted')],
      payoutRate: 250,
    ));

    expect(await container.read(riderEarningsProvider.future), 250);
  });

  test('an unreadable rate never turns into invented money', () async {
    final container = _container(_FakeRiderRepository(
      details: _setUp,
      deliveries: [_delivery('delivered')],
      payoutRate: 0,
    ));

    expect(await container.read(riderEarningsProvider.future), 0);
  });

  test('going offline sends the database value, not the enum name', () async {
    final fake = _FakeRiderRepository(details: _setUp);
    final container = _container(fake);

    await container.read(riderAvailabilityController.notifier).goOffline();

    expect(fake.called, ['availability:offline']);
  });

  test('going online sends the database value', () async {
    final fake = _FakeRiderRepository(details: _setUp);
    final container = _container(fake);

    await container.read(riderAvailabilityController.notifier).goOnline();

    expect(fake.called, ['availability:available']);
  });

  test('a refused availability change reaches the caller with the reason',
      () async {
    final fake = _FakeRiderRepository(
      details: _setUp,
      failWith: 'Finish your current delivery first',
    );
    final container = _container(fake);

    await expectLater(
      container.read(riderAvailabilityController.notifier).goOnline(),
      throwsA(isA<RiderRepositoryException>().having(
          (e) => e.message, 'message', 'Finish your current delivery first')),
    );
  });

  test('a transition invalidates the deliveries so the screen re-reads',
      () async {
    final fake = _FakeRiderRepository(details: _setUp);
    final container = _container(fake);

    await container.read(riderDeliveriesProvider.future);
    await container.read(riderTransitionController.notifier).claimOffer('a');

    expect(fake.called, ['claim']);
  });

  test('each transition reaches its own repository method', () async {
    final fake = _FakeRiderRepository(details: _setUp);
    final container = _container(fake);
    final controller = container.read(riderTransitionController.notifier);

    await controller.claimOffer('a');
    await controller.declineOffer('a');
    await controller.markPickedUp('a');
    await controller.completeDelivery('a');
    await controller.failDelivery('a', 'no answer');

    expect(fake.called, ['claim', 'decline', 'pickup', 'complete', 'fail']);
  });
}
