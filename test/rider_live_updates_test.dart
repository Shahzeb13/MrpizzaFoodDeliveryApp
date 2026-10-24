import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/rider/data/rider_repository.dart';
import 'package:mrpizza/features/rider/models/rider_delivery.dart';

/// A repository that counts reads and hands back whatever the test queued, with
/// no socket at all — which is exactly the state the rider panel was in when
/// realtime silently failed to connect.
class _FakeRiderRepository extends RiderRepository {
  _FakeRiderRepository() : super(signedInUserId: 'rider-uuid');

  int reads = 0;
  List<RiderDelivery> next = const [];

  @override
  Future<List<RiderDelivery>> fetchDeliveries() async {
    reads++;
    return next;
  }
}

/// Compressed stand-in for the real interval, so the behaviour is proven in
/// milliseconds instead of costing the suite twenty seconds per case.
const Duration _fastPoll = Duration(milliseconds: 60);
const Duration _settle = Duration(milliseconds: 30);

void main() {
  group('the safety-net poll is configured', () {
    test('it is short enough that a rider does not wait on it', () {
      // Long enough not to hammer the database, short enough that "he forgot to
      // refresh and missed the order" is not a 20x-too-long problem.
      expect(riderSafetyNetPollInterval.inSeconds, greaterThan(0));
      expect(riderSafetyNetPollInterval.inSeconds, lessThanOrEqualTo(30));
    });
  });

  group('the panel re-reads without being asked', () {
    test('a new assignment reaches the rider with no refresh and no push',
        () async {
      final repository = _FakeRiderRepository();

      // Subscribe exactly as `riderDeliveriesProvider` does.
      final emissions = <List<RiderDelivery>>[];
      final subscription = repository
          .streamDeliveries(safetyNetPollInterval: _fastPoll)
          .listen(emissions.add);

      // The first read happens on subscribe.
      await Future<void>.delayed(_settle);
      expect(repository.reads, greaterThanOrEqualTo(1));

      // The branch assigns an order. Nothing is pushed over the socket here, so
      // the only thing that can surface it is the poll.
      final readsBefore = repository.reads;
      await Future<void>.delayed(_fastPoll * 3);

      expect(
        repository.reads,
        greaterThan(readsBefore),
        reason: 'the panel must keep re-reading on its own, or a rider has to '
            'pull to refresh to discover work that is already waiting',
      );
      expect(emissions.length, greaterThan(1));

      await subscription.cancel();
    });

    test('cancelling the subscription stops the polling', () async {
      final repository = _FakeRiderRepository();

      final subscription = repository
          .streamDeliveries(safetyNetPollInterval: _fastPoll)
          .listen((_) {});
      await Future<void>.delayed(_settle);

      final readsWhileOpen = repository.reads;
      expect(readsWhileOpen, greaterThanOrEqualTo(1));

      await subscription.cancel();

      // Well past several intervals. A leaked timer would keep reading forever.
      await Future<void>.delayed(_fastPoll * 5);

      expect(
        repository.reads,
        readsWhileOpen,
        reason: 'the poll must be cancelled with the stream, or a rider who '
            'leaves the panel keeps hitting the database',
      );
    });
  });

  group('realtime is still subscribed, not replaced by the poll', () {
    test('the channel is still scoped to the rider own rows', () {
      // The poll is a floor, not a substitute: the push is what makes an
      // assignment appear in about a second instead of twenty.
      expect(
        riderAssignmentChannelName('rider-uuid'),
        'rider-assignments-rider-uuid',
      );
      expect(riderAssignmentChangeFilter('rider-uuid').column, 'rider_id');
    });
  });
}