import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/captured_location.dart';
import 'location_repository.dart';

/// Reverse geocodes coordinates to a street address using OpenStreetMap's
/// free Nominatim service — no API key and no billing account.
///
/// Nominatim's usage policy requires a descriptive User-Agent identifying the
/// application, and limits traffic to roughly one request per second. This app
/// only ever asks once per explicit "use my location" tap, so no queueing is
/// needed here.
class NominatimAddressTextLookup
    implements AddressTextLookup, AddressCoordinateLookup {
  static const String _defaultEndpoint = 'https://nominatim.openstreetmap.org';

  final http.Client client;
  final String userAgent;
  final String endpoint;

  NominatimAddressTextLookup({
    required this.userAgent,
    http.Client? client,
    this.endpoint = _defaultEndpoint,
  }) : client = client ?? http.Client();

  @override
  Future<String?> lookupAddressText(CapturedCoordinates coordinates) async {
    final uri = Uri.parse('$endpoint/reverse').replace(
      queryParameters: {
        'format': 'jsonv2',
        'lat': coordinates.latitude.toString(),
        'lon': coordinates.longitude.toString(),
      },
    );

    try {
      final response = await client
          .get(uri, headers: {'User-Agent': userAgent})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) return null;

      final displayName = body['display_name'];
      if (displayName is! String || displayName.trim().isEmpty) return null;

      return displayName.trim();
    } catch (_) {
      // Reverse geocoding is a convenience. Any failure (offline, rate limited,
      // blocked) just means the customer types their own address.
      return null;
    }
  }

  @override
  Future<CapturedCoordinates?> lookupCoordinates(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.parse('$endpoint/search').replace(
      queryParameters: {
        'format': 'jsonv2',
        'limit': '1',
        'q': trimmed,
      },
    );

    try {
      final response = await client
          .get(uri, headers: {'User-Agent': userAgent})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      if (body is! List || body.isEmpty) return null;

      final first = body.first;
      if (first is! Map<String, dynamic>) return null;

      final lat = double.tryParse('${first['lat']}');
      final lon = double.tryParse('${first['lon']}');
      if (lat == null || lon == null) return null;

      return CapturedCoordinates(latitude: lat, longitude: lon);
    } catch (_) {
      // Forward geocoding only decides which branch is closest. Any failure
      // just means the customer picks a branch by hand.
      return null;
    }
  }

  void dispose() => client.close();
}
