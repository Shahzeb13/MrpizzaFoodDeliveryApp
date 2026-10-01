import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/orders/data/coalesced_read_gate.dart';
import 'package:mrpizza/features/orders/models/order_tracking.dart';

/// Realtime and the safety-net poll are deliberately BOTH present — realtime for
/// immediacy, the poll because a backgrounded app or a dropped socket can miss
/// an event outright.
///
/// Keeping both is what makes this file necessary. The failure they invite is a
/// race: both call the same re-read, nothing orders them, and two reads in
/// flight can resolve in either order — the slow one landing last, having read
/// the database *before* the change the fast one saw. The customer watches a
/// status advance correctly, rewind, then crawl forward again on the next tick.
/// That reads as a broken realtime system even when both halves are perfect.
///
/// The gate is what makes them cooperate. It is tested directly, without a
/// Supabase client, because forcing the interleaving is the entire point.
void main() {
  group('realtime and the poll take turns rather than fight', () {
    test('a second request waits instead of running alongside the first',
        () async {
      final gate = CoalescedReadGate();

      var running = 0;
      var maxConcurrent = 0;
      final order = <int>[];

      Future<void> trackedRead(int id) async {
        running++;
        maxConcurrent = maxConcurrent > running ? maxConcurrent : running;
        order.add(id);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        running--;
      }

      final first = gate.request(() => trackedRead(1));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // A realtime event landing mid-read. It must not start a parallel read.
      gate.request(() => trackedRead(2));

      // Awaiting the first call covers the follow-up too: the gate loops until
      // nothing is queued.
      await first;

      expect(maxConcurrent, 1, reason: 'two reads overlapped');
      expect(order, [1, 2], reason: 'the second read started before the first finished');
    });

    test('a burst of triggers collapses into one follow-up read', () async {
      final gate = CoalescedReadGate();

      var reads = 0;
      Future<void> slowRead() async {
        reads++;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }

      final first = gate.request(slowRead);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Twenty-five realtime events arriving during one slow read.
      for (var i = 0; i < 25; i++) {
        gate.request(slowRead);
      }
      expect(gate.hasQueuedRead, isTrue);

      await first;
      await Future<void>.delayed(const Duration(milliseconds: 120));

      // One initial read plus at most ONE coalesced follow-up. Collapsing the
      // burst is what stops realtime from being turned into a request flood.
      expect(reads, lessThanOrEqualTo(2));
    });

    test('a request arriving during the follow-up is not lost either', () async {
      final gate = CoalescedReadGate();

      var reads = 0;
      Future<void> slowRead() async {
        reads++;
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }

      final first = gate.request(slowRead);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      gate.request(slowRead);
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Now arrive during the follow-up read.
      gate.request(slowRead);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Serialising must not mean dropping. If fixing the race quietly turned
      // realtime off, this is where it would show.
      expect(reads, greaterThanOrEqualTo(3));
    });

    test('a closed gate runs nothing more', () async {
      // A cancelled stream must not keep the database busy, and must not
      // resurrect itself through a queued follow-up.
      final gate = CoalescedReadGate();

      var reads = 0;
      final first = gate.request(() async {
        reads++;
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      gate.request(() async => reads++);
      gate.close();
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(reads, 1);
    });

    test('of a burst, the work that runs last is the most recent request', () async {
      // This is the property the whole design rests on. Coalescing means not
      // every trigger gets its own read — they all want the same current state,
      // so running them in order would spend requests deriving answers the next
      // one supersedes. What MUST hold is that the read which runs last is the
      // one from the most recent trigger, because that is the one whose data the
      // customer ends up seeing.
      final gate = CoalescedReadGate();
      final order = <int>[];

      final futures = <Future<void>>[];
      for (var i = 1; i <= 5; i++) {
        futures.add(gate.request(() async {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          order.add(i);
        }));
      }

      for (final future in futures) {
        await future;
      }

      // Trigger 1 runs. Triggers 2-5 arrive while it is running and collapse
      // into one follow-up — carried by the LAST of them.
      expect(order, [1, 5]);
      expect(order.last, 5);
    });
  });

  group('a stage still never walks backwards', () {
    // Belt and braces on top of the gate. The gate stops two reads racing; this
    // stops a single read that observed something older than what is already on
    // screen, which a stale RPC result or a status-history row that landed
    // after the status update can still produce.
    test('realtime delivering a newer stage wins', () {
      expect(
        isOrderStageRegression(
          OrderStage.preparingInKitchen,
          OrderStage.outForDelivery,
        ),
        isFalse,
      );
    });

    test('a stale poll cannot rewind what realtime already showed', () {
      expect(
        isOrderStageRegression(
          OrderStage.outForDelivery,
          OrderStage.preparingInKitchen,
        ),
        isTrue,
      );
    });

    test('a cancellation is never refused as a regression', () {
      expect(
        isOrderStageRegression(OrderStage.outForDelivery, OrderStage.cancelled),
        isFalse,
      );
    });
  });
}