import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mrpizza/features/location/data/nominatim_address_lookup.dart';
import 'package:mrpizza/features/location/models/captured_location.dart';

void main() {
  const coordinates = CapturedCoordinates(latitude: 34.2045, longitude: 73.24);

  NominatimAddressTextLookup buildLookup(
    Future<http.Response> Function(http.Request request) handler,
  ) {
    return NominatimAddressTextLookup(
      client: MockClient((request) => handler(request)),
      userAgent: 'MrPizza/1.0 (test@example.com)',
    );
  }

  test('asks OpenStreetMap for the address of the captured coordinates',
      () async {
    late Uri requestedUri;
    final lookup = buildLookup((request) async {
      requestedUri = request.url;
      return http.Response(
        jsonEncode({'display_name': 'Al Mansoor Town, Abbottabad'}),
        200,
      );
    });

    final address = await lookup.lookupAddressText(coordinates);

    expect(requestedUri.host, 'nominatim.openstreetmap.org');
    expect(requestedUri.path, '/reverse');
    expect(requestedUri.queryParameters['format'], 'jsonv2');
    expect(requestedUri.queryParameters['lat'], '34.2045');
    expect(requestedUri.queryParameters['lon'], '73.24');
    expect(address, 'Al Mansoor Town, Abbottabad');
  });

  test('identifies the app in the User-Agent header as usage policy requires',
      () async {
    late String? userAgent;
    final lookup = buildLookup((request) async {
      userAgent = request.headers['User-Agent'];
      return http.Response(jsonEncode({'display_name': 'Somewhere'}), 200);
    });

    await lookup.lookupAddressText(coordinates);

    expect(userAgent, contains('MrPizza'));
  });

  test('returns nothing when OpenStreetMap has no address for the point',
      () async {
    final lookup = buildLookup((_) async => http.Response('{}', 200));

    expect(await lookup.lookupAddressText(coordinates), isNull);
  });

  test('returns nothing when OpenStreetMap rejects the request', () async {
    final lookup = buildLookup((_) async => http.Response('nope', 503));

    expect(await lookup.lookupAddressText(coordinates), isNull);
  });

  test('returns nothing when the response is not valid JSON', () async {
    final lookup = buildLookup((_) async => http.Response('<html>', 200));

    expect(await lookup.lookupAddressText(coordinates), isNull);
  });
}
