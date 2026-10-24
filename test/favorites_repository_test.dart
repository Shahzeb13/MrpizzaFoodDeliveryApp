import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mrpizza/features/menu/data/favorites_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _requests = <http.Request>[];

/// PostgREST's response parser dereferences `response.request!`, so a mock
/// response has to carry the request that produced it.
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
        jsonEncode({'message': 'permission denied for table favorites'}),
        403,
      );
    }),
  );
}

void main() {
  setUp(_requests.clear);

  group('reading saved dishes', () {
    test('returns the menu item ids in the order the database gave them',
        () async {
      final repository = FavoritesRepository(
        client: _clientReturning([
          {'menu_item_id': 'zinger'},
          {'menu_item_id': 'tikka'},
        ]),
      );

      expect(
        await repository.fetchFavoriteItemIds('customer-uuid'),
        ['zinger', 'tikka'],
      );
    });

    test('is scoped to that one customer, never to every customer', () async {
      // Without the filter this returns one row per customer in the system, so
      // a shared phone would show the previous account's saved dishes.
      final repository = FavoritesRepository(client: _clientReturning([]));

      await repository.fetchFavoriteItemIds('customer-uuid');

      expect(_requests, hasLength(1));
      expect(_requests.single.method, 'GET');
      final query = _requests.single.url.query;
      expect(query, contains('user_id=eq.customer-uuid'));
      // Newest first, so the screen leads with what was saved most recently.
      expect(query, contains('created_at.desc'));
      expect(query, contains('select=menu_item_id'));
    });

    test('skips rows with no item id instead of rendering a blank dish', () {
      final repository = FavoritesRepository(
        client: _clientReturning([
          {'menu_item_id': 'zinger'},
          {'menu_item_id': null},
          {'menu_item_id': ''},
        ]),
      );

      return expectLater(
        repository.fetchFavoriteItemIds('customer-uuid'),
        completion(['zinger']),
      );
    });

    test('a failed read throws rather than reporting an empty list', () async {
      // An empty list and a failed read look identical downstream, and the
      // screen turns one into "you have not saved anything" — which is a
      // different, and wrong, thing to tell a customer.
      final repository = FavoritesRepository(client: _clientFailing());

      await expectLater(
        repository.fetchFavoriteItemIds('customer-uuid'),
        throwsA(anything),
      );
    });
  });

  group('saving a dish', () {
    test('writes the customer and the item', () async {
      final repository = FavoritesRepository(client: _clientReturning([]));

      await repository.addFavorite(userId: 'customer-uuid', itemId: 'zinger');

      expect(_requests, hasLength(1));
      expect(_requests.single.method, 'POST');
      expect(jsonDecode(_requests.single.body), {
        'user_id': 'customer-uuid',
        'menu_item_id': 'zinger',
      });
    });

    test('is idempotent, so a double tap on the heart is not an error', () async {
      // The table is unique on (user_id, menu_item_id). A plain insert turns
      // the second tap into a constraint violation, which the customer sees as
      // a failed save for a tap they were entitled to make.
      final repository = FavoritesRepository(client: _clientReturning([]));

      await repository.addFavorite(userId: 'customer-uuid', itemId: 'zinger');

      final headers = _requests.single.headers;
      expect(headers['prefer'], contains('resolution=ignore-duplicates'));
      expect(_requests.single.url.query, contains('on_conflict'));
    });
  });

  group('removing a dish', () {
    test('deletes the matching pair and nothing wider', () async {
      final repository = FavoritesRepository(client: _clientReturning([]));

      await repository.removeFavorite(
        userId: 'customer-uuid',
        itemId: 'zinger',
      );

      expect(_requests, hasLength(1));
      expect(_requests.single.method, 'DELETE');
      final query = _requests.single.url.query;
      expect(query, contains('user_id=eq.customer-uuid'));
      expect(query, contains('menu_item_id=eq.zinger'));
    });

    test('a failed removal throws so the heart can be put back', () async {
      final repository = FavoritesRepository(client: _clientFailing());

      await expectLater(
        repository.removeFavorite(userId: 'customer-uuid', itemId: 'zinger'),
        throwsA(anything),
      );
    });
  });
}
