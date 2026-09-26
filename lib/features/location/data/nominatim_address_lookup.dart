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
class NominatimAddressTextLookup implements AddressTextLookup {
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

  void dispose() => client.close();
}
