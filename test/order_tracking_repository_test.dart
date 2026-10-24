import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mrpizza/features/orders/data/order_tracking_repository.dart';
import 'package:mrpizza/features/orders/models/order_tracking.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What `order_tracking()` actually answers, in both of the shapes that matter
/// here: an order that exists, and a refusal for one that does not.
///
/// The refusal is not an edge case invented for a test. It is the shape the app
/// produces itself, every time a customer opens PayFast's page and then walks
/// away: `discard_unpaid_order` deletes the row, and the next read of an order
/// this app already had on screen comes back exactly like this.
const _orderId = '62243bf7-1e81-4e7c-9458-66be0e95606e';

Map<String, dynamic> _orderExists() {
  return {
    'ok': true,
    'order': {
      'id': _orderId,
      'bill_number': 'ABT-072',
      'status': 'confirmed',
      'order_type': 'delivery',
      'subtotal': 2377.65,
      'tax': 190.21,
      'delivery_charges': 150,
      'discount_amount': 0,
      'total': 2717.86,
      'created_at': '2026-10-19T10:00:00+00:00',
      'delivery_address': 'Triple one hotel near comsats',
      'branch_name': 'Mr. Pizza - Abbottabad',
    },
    'items': <Object>[],
    'rider': null,
    'timeline': <Object>[],
  };
}

Map<String, dynamic> _orderMissing() {
  return {'ok': false, 'message': 'Order not found.'};
}

/// Stands in for a reply that never arrived: a 5xx, which postgrest raises as a
/// `PostgrestException` rather than as an [OrderTrackingException].
class _GatewayFailure {
  const _GatewayFailure();
}

/// A client that replays [responses] in order, repeating the last one once they
/// run out so a fast poll does not exhaust the script mid-test.
///
/// The URL points at a closed port on purpose. `watchOrderTracking` opens a
/// realtime channel, and this keeps that attempt from reaching the network;
/// realtime_client treats the refusal as a delay, which is exactly the
/// behaviour under test anyway.
SupabaseClient _clientServing(List<Object> responses) {
  var call = 0;
  return SupabaseClient(
    'http://127.0.0.1:1',
    'test-anon-key',
    httpClient: MockClient((request) async {
      final index = call < responses.length ? call : responses.length - 1;
      call++;
      final response = responses[index];

      // PostgREST's response parser dereferences `response.request!`, so a mock
      // response has to carry the request that produced it.
      final status = response is _GatewayFailure ? 500 : 200;
      final body =
          response is _GatewayFailure ? {'message': 'upstream failure'} : response;

      return http.Response(
        jsonEncode(body),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

/// Compressed stand-in for the real twenty second poll, so each case proves the
/// behaviour in milliseconds rather than costing the suite half a minute.
const Duration _fastPoll = Duration(milliseconds: 40);
const Duration _settle = Duration(milliseconds: 250);

void main() {
  group('an order that has been deleted', () {
    test('empties the stream instead of leaving the last state on screen',
        () async {
      // The bug this whole file is about. The bar had already painted a real
      // order, so `hasDeliveredOnce` was true and the refusal landed on the
      // "keep the last thing the database gave us" branch — which for a deleted
      // order means showing a pizza being cooked for a bill number the database
      // has no row for, with nothing to tap and nothing to dismiss.
      final repository = OrderTrackingRepository(
        client: _clientServing([_orderExists(), _orderMissing()]),
      );

      final seen = <Object?>[];
      final errors = <Object>[];
      final subscription = repository
          .watchOrderTracking(_orderId, safetyNetPollInterval: _fastPoll)
          .listen(seen.add, onError: errors.add);

      await Future<void>.delayed(_settle);
      await subscription.cancel();

      expect(seen.whereType<OrderTracking>(), isNotEmpty);
      expect(
        seen.last,
        isNull,
        reason: 'a refusal after a real read means the order is gone, and the '
            'bar has to be told rather than left holding a deleted order',
      );
      expect(errors, isEmpty);
    });
  });

  group('a read that never arrived', () {
    test('keeps the last state the database actually gave us', () async {
      // The opposite verdict, and it has to stay that way. A timeout on a phone
      // in a lift is not a cancelled order, and blanking a delivery screen
      // because one poll failed is worse than showing data a few seconds old.
      final repository = OrderTrackingRepository(
        client: _clientServing([_orderExists(), const _GatewayFailure()]),
      );

      final seen = <Object?>[];
      final errors = <Object>[];
      final subscription = repository
          .watchOrderTracking(_orderId, safetyNetPollInterval: _fastPoll)
          .listen(seen.add, onError: errors.add);

      await Future<void>.delayed(_settle);
      await subscription.cancel();

      expect(seen, isNotEmpty);
      expect(
        seen.every((value) => value is OrderTracking),
        isTrue,
        reason: 'nothing was ever published about the order being gone',
      );
      expect(errors, isEmpty);
    });
  });

  group('a refusal before anything was ever shown', () {
    test('is still reported as an error, so the screen can explain itself', (
      ) async {
      // There is no stale state to contradict here, so the existing contract
      // stands: the tracking screen says what went wrong rather than claiming
      // the customer has no orders.
      final repository = OrderTrackingRepository(
        client: _clientServing([_orderMissing()]),
      );

      final seen = <Object?>[];
      final errors = <Object>[];
      final subscription = repository
          .watchOrderTracking(_orderId, safetyNetPollInterval: _fastPoll)
          .listen(seen.add, onError: errors.add);

      await Future<void>.delayed(_settle);
      await subscription.cancel();

      expect(errors.whereType<OrderTrackingException>(), isNotEmpty);
    });
  });

  group('the safety net', () {
    test('is configured short enough that nobody is misled for long', () {
      expect(
        orderTrackingSafetyNetPollInterval.inSeconds,
        greaterThan(0),
      );
      expect(
        orderTrackingSafetyNetPollInterval.inSeconds,
        lessThanOrEqualTo(30),
      );
    });
  });
}