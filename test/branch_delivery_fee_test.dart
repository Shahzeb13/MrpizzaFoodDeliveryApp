import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mrpizza/features/orders/data/orders_repository.dart';

/// `store_settings` is keyed by `branch_id` now, so the only question that
/// matters when reading a delivery fee is whether the request is filtered to
/// the branch that will fulfil the order.
///
/// A missing filter is not a crash. With two branches the read succeeds and
/// returns whichever row the database felt like, which is how an Abbottabad
/// customer ends up quoted the Mansehra fee. Nothing in the app would notice.
///
void main() {
  final requests = <http.Request>[];

  SupabaseClient clientReturning(Object? body) => SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode(body),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

  setUp(requests.clear);

  String queryOf(http.Request request) => request.url.query;

  test('the delivery fee read is filtered to the fulfilling branch', () async {
    final repository = OrdersRepository(
      client: clientReturning([
        {'branch_id': 'abt-branch-id', 'delivery_fee': 150}
      ]),
    );

    await repository.fetchBranchDeliveryFee('abt-branch-id');

    expect(requests, hasLength(1));
    final query = queryOf(requests.single);
    expect(
      query,
      contains('branch_id=eq.abt-branch-id'),
      reason: 'an unfiltered read silently returns another branch\'s fee',
    );
  });

  test('the query targets store_settings, not some other table', () async {
    final repository = OrdersRepository(client: clientReturning([]));

    await repository.fetchBranchDeliveryFee('abt-branch-id');

    expect(requests.single.url.path, contains('/rest/v1/store_settings'));
  });

  test('a branch with no settings row reports null, not zero', () async {
    // Zero would read as free delivery, which is the opposite of "not
    // configured" and would quietly give the order away.
    final repository = OrdersRepository(client: clientReturning([]));

    expect(await repository.fetchBranchDeliveryFee('msh-branch-id'), isNull);
  });

  test('each branch is asked about itself, never a shared row', () async {
    final repository = OrdersRepository(client: clientReturning([]));

    await repository.fetchBranchDeliveryFee('abt-branch-id');
    final abbottabadQuery = queryOf(requests.last);

    await repository.fetchBranchDeliveryFee('msh-branch-id');
    final mansehraQuery = queryOf(requests.last);

    expect(abbottabadQuery, isNot(mansehraQuery));
    expect(mansehraQuery, contains('branch_id=eq.msh-branch-id'));
  });
}
