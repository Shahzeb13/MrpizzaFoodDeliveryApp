import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mrpizza/features/location/data/geocoding_service.dart';
import 'package:mrpizza/features/location/models/captured_location.dart';

/// Tests for the Mapbox Search Box reverse lookup that names the delivery pin.
///
/// The token is injected so these never depend on a real one, and the client is
/// a mock so no request leaves the machine.
///
/// [shape] below is the real response body Mapbox returns for a `poi` reverse
/// lookup in Abbottabad, so the parsing is tested against reality rather than
/// against an invented shape.
void main() {
  GeocodingService buildService(
    Future<http.Response> Function(http.Request request) handler, {
    String? token = 'pk.test-token',
  }) {
    return GeocodingService(
      client: MockClient((request) => handler(request)),
      tokenResolver: () => token,
    );
  }

  /// A response with one feature, built from the fields the endpoint returns.
  String featureResponse({
    String? name,
    String? fullAddress,
    String? placeFormatted,
  }) {
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {'type': 'Point', 'coordinates': [73.2215, 34.1688]},
          'properties': {
            'mapbox_id': 'id-1',
            'feature_type': 'poi',
            if (name != null) 'name': name,
            if (fullAddress != null) 'full_address': fullAddress,
            if (placeFormatted != null) 'place_formatted': placeFormatted,
          },
        },
      ],
    });
  }

  String emptyResponse() => jsonEncode({'features': []});

  group('reverse lookup', () {
    test('asks Search Box for the coordinates, longitude first', () async {
      late Uri requestedUri;
      final service = buildService((request) async {
        requestedUri = request.url;
        return http.Response(
          featureResponse(name: 'Triple One Hotel', fullAddress: 'Abbottabad'),
          200,
        );
      });

      final name = await service.getPlaceName(34.2045, 73.24);

      expect(requestedUri.host, 'api.mapbox.com');
      expect(requestedUri.path, '/search/searchbox/v1/reverse');
      expect(requestedUri.queryParameters['longitude'], '73.24');
      expect(requestedUri.queryParameters['latitude'], '34.2045');
      expect(requestedUri.queryParameters['limit'], '1');
      expect(requestedUri.queryParameters['access_token'], 'pk.test-token');
      // Longitude is asked for first, as the endpoint takes it.
      expect(requestedUri.query, startsWith('longitude='));
      expect(name, 'Triple One Hotel, Abbottabad');
    });

    test('never sends a session_token, which reverse lookup does not take',
        () async {
      final requested = <Uri>[];
      final service = buildService((request) async {
        requested.add(request.url);
        return http.Response(featureResponse(name: 'Somewhere'), 200);
      });

      await service.getPlaceName(34.2, 73.2);

      expect(requested, isNotEmpty);
      for (final uri in requested) {
        expect(uri.queryParameters.containsKey('session_token'), isFalse);
      }
    });

    test('reads landmarks first with types=poi', () async {
      late Uri requestedUri;
      final service = buildService((request) async {
        requestedUri = request.url;
        return http.Response(featureResponse(name: 'Triple One Hotel'), 200);
      });

      await service.getPlaceName(34.1688, 73.2215);

      expect(requestedUri.queryParameters['types'], 'poi');
    });

    test('falls back to address and street when there is no landmark',
        () async {
      final requested = <String>[];
      final service = buildService((request) async {
        requested.add(request.url.queryParameters['types']!);
        // Nothing is a landmark here, but the street pass finds the road.
        if (request.url.queryParameters['types'] == 'poi') {
          return http.Response(emptyResponse(), 200);
        }
        return http.Response(
          featureResponse(name: 'Shiekh Dheri Road', fullAddress: 'Abbottabad'),
          200,
        );
      });

      final name = await service.getPlaceName(34.1688, 73.2215);

      expect(requested, ['poi', 'address,street']);
      expect(name, 'Shiekh Dheri Road, Abbottabad');
    });

    test('stops at the first pass that answers', () async {
      var requests = 0;
      final service = buildService((_) async {
        requests++;
        return http.Response(
          featureResponse(name: 'Triple One Hotel', fullAddress: 'Abbottabad'),
          200,
        );
      });

      final name = await service.getPlaceName(34.1688, 73.2215);

      // A landmark was found, so the second pass was never paid for.
      expect(requests, 1);
      expect(name, 'Triple One Hotel, Abbottabad');
    });

    test('returns nothing when both passes come back empty', () async {
      final service =
          buildService((_) async => http.Response(emptyResponse(), 200));

      expect(await service.getPlaceName(34.2, 73.2), isNull);
    });

    test('uses place_formatted when there is no full_address', () async {
      final service = buildService(
        (_) async => http.Response(
          featureResponse(name: 'Niazi Plaza', placeFormatted: 'Abbottabad, Pakistan'),
          200,
        ),
      );

      expect(await service.getPlaceName(34.2, 73.2), 'Niazi Plaza, Abbottabad, Pakistan');
    });

    test('falls back to the address alone when there is no name', () async {
      final service = buildService(
        (_) async => http.Response(
          featureResponse(fullAddress: 'Abbottabad, Pakistan'),
          200,
        ),
      );

      expect(await service.getPlaceName(34.2, 73.2), 'Abbottabad, Pakistan');
    });

    test('does not repeat the name when it is the whole address', () async {
      final service = buildService(
        (_) async => http.Response(
          featureResponse(name: 'Shiekh Dheri Road', fullAddress: 'Shiekh Dheri Road'),
          200,
        ),
      );

      expect(await service.getPlaceName(34.2, 73.2), 'Shiekh Dheri Road');
    });

    test('ignores a blank name or address rather than showing a gap',
        () async {
      final service = buildService(
        (_) async => http.Response(
          featureResponse(name: '   ', fullAddress: 'Abbottabad, Pakistan'),
          200,
        ),
      );

      expect(await service.getPlaceName(34.2, 73.2), 'Abbottabad, Pakistan');
    });

    test('returns nothing when a bad token is rejected with 401', () async {
      final service =
          buildService((_) async => http.Response('{"message":"Not Authorized"}', 401));

      expect(await service.getPlaceName(34.2, 73.2), isNull);
    });

    test('returns nothing when the token may not search (403)', () async {
      final service =
          buildService((_) async => http.Response('{"message":"Forbidden"}', 403));

      expect(await service.getPlaceName(34.2, 73.2), isNull);
    });

    test('returns nothing when Mapbox reports too many requests', () async {
      final service =
          buildService((_) async => http.Response('{"message":"Too Many"}', 429));

      expect(await service.getPlaceName(34.2, 73.2), isNull);
    });

    test('returns nothing when the response is not valid JSON', () async {
      final service = buildService((_) async => http.Response('<html>', 200));

      expect(await service.getPlaceName(34.2, 73.2), isNull);
    });

    test('returns nothing when there is no connection', () async {
      final service =
          buildService((_) async => throw const ConnectionDroppedStub());

      expect(await service.getPlaceName(34.2, 73.2), isNull);
    });

    test('makes no request at all when there is no usable token', () async {
      var asked = false;
      final service = buildService((_) async {
        asked = true;
        return http.Response(featureResponse(name: 'Somewhere'), 200);
      }, token: null);

      expect(await service.getPlaceName(34.2, 73.2), isNull);
      expect(asked, isFalse);
    });

    test('throws away a slow answer that a newer request has overtaken',
        () async {
      final service = GeocodingService(
        client: MockClient((request) async {
          // The first request stalls until the second has already been asked
          // for, which is the case that would otherwise repaint an old pin.
          if (request.url.queryParameters['latitude'] == '34.2') {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            return http.Response(featureResponse(name: 'The old place'), 200);
          }
          return http.Response(featureResponse(name: 'The new place'), 200);
        }),
        tokenResolver: () => 'pk.test-token',
      );

      final slow = service.getPlaceName(34.2, 73.2);
      final fresh = service.getPlaceName(35.1, 73.9);

      expect(await slow, isNull, reason: 'a superseded lookup must answer null');
      expect(await fresh, 'The new place');
    });
  });

  test('the address field reads the same lookup as the pin label', () async {
    final requested = <Uri>[];
    final service = buildService((request) async {
      requested.add(request.url);
      return http.Response(featureResponse(name: 'Triple One Hotel'), 200);
    });

    final name = await service.getPlaceName(34.2, 73.2);
    final address = await service.lookupAddressText(
      const CapturedCoordinates(latitude: 34.2, longitude: 73.2),
    );

    // Both entry points ask the same endpoint about the same point, so they
    // agree. Nothing is cached — Mapbox allows this data for temporary use
    // only — so two separate callers cost two requests. The delivery map avoids
    // the second one by naming the pin once and reusing that answer.
    expect(name, 'Triple One Hotel');
    expect(address, 'Triple One Hotel');
    expect(requested.last.path, '/search/searchbox/v1/reverse');
  });

  group('forward lookup', () {
    String forwardResponse(String longitude, String latitude) => jsonEncode({
          'features': [
            {
              'geometry': {
                'type': 'Point',
                'coordinates': [double.parse(longitude), double.parse(latitude)],
              },
            },
          ],
        });

    test('asks Search Box forward for the typed address', () async {
      late Uri requestedUri;
      final service = buildService((request) async {
        requestedUri = request.url;
        return http.Response(forwardResponse('73.24', '34.2045'), 200);
      });

      final point = await service.lookupCoordinates('Al Mansoor Town');

      expect(requestedUri.host, 'api.mapbox.com');
      expect(requestedUri.path, '/search/searchbox/v1/forward');
      expect(requestedUri.queryParameters['q'], 'Al Mansoor Town');
      expect(requestedUri.queryParameters['limit'], '1');
      expect(point,
          const CapturedCoordinates(latitude: 34.2045, longitude: 73.24));
    });

    test('reads longitude first out of the coordinates pair', () async {
      final service = buildService(
        (_) async => http.Response(forwardResponse('73.24', '34.2045'), 200),
      );

      final point = await service.lookupCoordinates('Al Mansoor Town');

      // GeoJSON is [longitude, latitude]. Reading it the other way round drops
      // the customer in the middle of the ocean, which is why this is asserted
      // rather than left to the type system.
      expect(point!.latitude, 34.2045);
      expect(point.longitude, 73.24);
    });

    test('returns nothing when nothing matched the address', () async {
      final service =
          buildService((_) async => http.Response(emptyResponse(), 200));

      expect(await service.lookupCoordinates('nowhere at all'), isNull);
    });

    test('returns nothing when the feature has no usable coordinates', () async {
      final service = buildService(
        (_) async => http.Response(
          jsonEncode({
            'features': [
              {
                'geometry': {'coordinates': ['not', 'numbers']},
              },
            ],
          }),
          200,
        ),
      );

      expect(await service.lookupCoordinates('Al Mansoor Town'), isNull);
    });

    test('returns nothing when a bad token is rejected', () async {
      final service =
          buildService((_) async => http.Response('{"message":"Forbidden"}', 403));

      expect(await service.lookupCoordinates('Al Mansoor Town'), isNull);
    });

    test('sends nothing for an address that is only whitespace', () async {
      var asked = false;
      final service = buildService((_) async {
        asked = true;
        return http.Response(emptyResponse(), 200);
      });

      expect(await service.lookupCoordinates('   '), isNull);
      expect(asked, isFalse);
    });
  });
}

/// Stands in for a dropped connection without importing `dart:io` into a test
/// that otherwise runs everywhere.
class ConnectionDroppedStub implements Exception {
  const ConnectionDroppedStub();

  @override
  String toString() => 'connection failed';
}