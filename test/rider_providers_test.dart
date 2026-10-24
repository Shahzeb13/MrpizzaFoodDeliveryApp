import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/rider/data/rider_repository.dart';
import 'package:mrpizza/features/rider/models/rider_delivery.dart';
import 'package:mrpizza/features/rider/providers/rider_providers.dart';

class _FakeRiderRepository extends RiderRepository {
  _FakeRiderRepository({
    this.details,
    this.failWith,
  });

  final RiderDetails? details;
  final String? failWith;
  final List<String> called = [];

  @override
  Future<RiderDetails?> fetchRiderDetails() async => details;

  @override
  Stream<List<RiderDelivery>> streamDeliveries({
    Duration safetyNetPollInterval = riderSafetyNetPollInterval,
  }) =>
      Stream<List<RiderDelivery>>.value(const <RiderDelivery>[]);

  @override
  Future<List<RiderDelivery>> fetchDeliveries() async =>
      const <RiderDelivery>[];

  @override
  Future<void> claimOffer(String id) async {
    if (failWith != null) throw RiderRepositoryException(failWith!);
    called.add('claim');
  }

  @override
  Future<void> declineOffer(String id) async => called.add('decline');
  @override
  Future<void> markPickedUp(String id) async => called.add('pickup');
  @override
  Future<void> completeDelivery(String id) async => called.add('complete');
  @override
  Future<void> failDelivery(String id, String reason) async {
    if (failWith != null) throw RiderRepositoryException(failWith!);
    called.add('fail');
  }
}

const _setUp = RiderDetails(
  branchId: 'b1',
  branchName: 'Abbottabad',
  branchAddress: 'Niazi Road',
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

  test('the rider record carries the branch it belongs to', () async {
    final container = _container(_FakeRiderRepository(details: _setUp));

    final details = await container.read(riderDetailsProvider.future);
    expect(details?.branchId, 'b1');
    expect(details?.branchName, 'Abbottabad');
  });

  test('a refused transition reaches the caller with the reason', () async {
    final fake = _FakeRiderRepository(
      details: _setUp,
      failWith: 'Finish your current delivery first',
    );
    final container = _container(fake);

    await expectLater(
      container.read(riderTransitionController.notifier).claimOffer('a'),
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
