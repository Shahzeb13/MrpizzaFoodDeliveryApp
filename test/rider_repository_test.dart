import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mrpizza/features/rider/data/rider_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _requests = <http.Request>[];

/// Postgestrel's response parser dereferences `response.request!`, so a mock
/// response must carry the request that produced it.
http.Response _response(http.Request request, String body, int statusCode) =>
    http.Response(
      body,
      statusCode,
      request: request,
      headers: {'content-type': 'application/json'},
    );

SupabaseClient _clientReturning(Object? body) {
  _requests.clear();
  return SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: MockClient((request) async {
      _requests.add(request);
      return _response(request, jsonEncode(body), 200);
    }),
  );
}

SupabaseClient _clientFailing() {
  _requests.clear();
  return SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: MockClient((request) async {
      _requests.add(request);
      return _response(
        request,
        jsonEncode({'message': 'This delivery is no longer available'}),
        400,
      );
    }),
  );
}

String _functionCalledBy(http.Request request) =>
    request.url.path.split('/rest/v1/rpc/').last;

void main() {
  setUp(_requests.clear);

  test('claiming an offer calls rider_claim_offer for that assignment', () async {
    final repository = RiderRepository(client: _clientReturning({}));
    await repository.claimOffer('assignment-1');

    expect(_requests, hasLength(1));
    expect(_functionCalledBy(_requests.single), 'rider_claim_offer');
    expect(_requests.single.method, 'POST');
    expect(jsonDecode(_requests.single.body),
        {'p_assignment_id': 'assignment-1'});
  });

  test('every transition maps to its own database function', () async {
    final repository = RiderRepository(client: _clientReturning({}));
    await repository.declineOffer('a');
    await repository.markPickedUp('a');
    await repository.completeDelivery('a');
    await repository.failDelivery('a', 'customer not answering');

    expect(_requests.map(_functionCalledBy).toList(), [
      'rider_decline_offer',
      'rider_mark_picked_up',
      'rider_complete_delivery',
      'rider_fail_delivery',
    ]);
    expect(jsonDecode(_requests.last.body), {
      'p_assignment_id': 'a',
      'p_reason': 'customer not answering',
    });
  });

  test('setting availability calls rider_set_availability', () async {
    final repository = RiderRepository(client: _clientReturning({}));
    await repository.setAvailability('available');

    expect(_functionCalledBy(_requests.single), 'rider_set_availability');
    expect(jsonDecode(_requests.single.body), {'p_status': 'available'});
  });

  test('a rejected transition surfaces the database message', () async {
    final repository = RiderRepository(client: _clientFailing());

    await expectLater(
      repository.claimOffer('a'),
      throwsA(
        isA<RiderRepositoryException>()
            .having((e) => e.message, 'message',
                'This delivery is no longer available'),
      ),
    );
  });

  test('deliveries are read through the rider_deliveries function', () async {
    final repository = RiderRepository(
      client: _clientReturning([
        {
          'assignment_id': 'a1',
          'assignment_status': 'assigned',
          'order_id': 'o1',
          'bill_number': '#MP-1',
          'customer_name': 'Usama',
          'customer_phone': '0300',
          'delivery_address': 'Mandian',
          'delivery_latitude': 34.16,
          'delivery_longitude': 73.22,
          'branch_name': 'Abbottabad',
          'branch_address': 'Niazi Road',
          'item_summary': '1x Zinger',
          'item_count': 1,
          'assigned_at': '2026-09-28T10:00:00Z',
          'picked_up_at': null,
          'delivered_at': null,
        }
      ]),
    );

    final deliveries = await repository.fetchDeliveries();

    expect(deliveries, hasLength(1));
    expect(deliveries.single.assignmentId, 'a1');
    expect(_functionCalledBy(_requests.single), 'rider_deliveries');
  });

  test('the payout rate is read from store_settings', () async {
    final repository = RiderRepository(
      client: _clientReturning({'rider_payout_per_delivery': 300}),
    );

    expect(await repository.fetchPayoutRate(), 300);
  });

  test('an unreadable payout rate is zero, never a guess', () async {
    expect(
      await RiderRepository(client: _clientReturning({})).fetchPayoutRate(),
      0,
    );
    expect(
      await RiderRepository(client: _clientReturning([])).fetchPayoutRate(),
      0,
    );
  });

  test('a missing rider record is null so the screen can say so', () async {
    final repository = RiderRepository(client: _clientReturning(null));

    expect(await repository.fetchRiderDetails(), isNull);
  });

  test('the rider record is read for this rider only, never every rider',
      () async {
    // Without an explicit filter this returns one row per rider in the whole
    // system, and maybeSingle() throws "multiple rows" — which looked exactly
    // like "this rider has no record" and showed the wrong message.
    final repository = RiderRepository(
      client: _clientReturning({'branch_id': 'b1', 'status': 'available'}),
      signedInUserId: 'rider-uuid',
    );

    await repository.fetchRiderDetails();

    expect(_requests, hasLength(1));
    final query = _requests.single.url.query;
    expect(query, contains('profile_id=eq.rider-uuid'));
  });

  test('with no signed-in rider there is nothing to fetch', () async {
    final repository = RiderRepository(client: _clientReturning({}));

    expect(await repository.fetchRiderDetails(), isNull);
    expect(_requests, isEmpty);
  });

  test('a failed read is not reported as an account that is not set up', () async {
    // Reporting a network or permission failure as "not set up yet" tells the
    // rider to go and ask the branch for an account they already have.
    final repository = RiderRepository(
      client: _clientFailing(),
      signedInUserId: 'rider-uuid',
    );

    await expectLater(repository.fetchRiderDetails(), throwsA(anything));
  });

  test('the repository never writes the rider tables directly', () {
    final source = File(
      'lib/features/rider/data/rider_repository.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('.update(')));
    expect(source, isNot(contains('.insert(')));
    expect(source, isNot(contains('.delete(')));
  });
}
