import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/mapbox_config.dart';
import '../models/captured_location.dart';
import 'location_repository.dart';

/// Names the coordinates under the delivery map's pin, and turns a typed
/// address back into coordinates, using the Mapbox **Search Box API**.
///
/// This is a plain HTTP call. The Maps SDK already draws the map and the token
/// is already in the app, so no second SDK is involved.
///
/// It is the app's single geocoder: the delivery map's pin, the address box that
/// fills itself in, and the pin a typed address is given all come from here, on
/// the same public Mapbox token the map itself runs on.
///
/// Search Box replaced Geocoding v6 because v6 dropped point-of-interest data
/// entirely — it could only ever answer "Abbottabad", never "a hotel on this
/// road". The `poi` pass below is what makes a landmark nameable.
///
/// Results are for **temporary** use only, which is the Mapbox Terms of Service
/// requirement for this data. Nothing is written to the database or kept in a
/// cache: a cached place name would go stale the moment the pin moves, and there
/// is nothing to invalidate it against.
class GeocodingService implements AddressTextLookup, AddressCoordinateLookup {
  static const String _defaultReverseEndpoint =
      'https://api.mapbox.com/search/searchbox/v1/reverse';

  static const String _defaultForwardEndpoint =
      'https://api.mapbox.com/search/searchbox/v1/forward';

  /// The reverse passes, tried in order and stopped at the first that answers.
  ///
  /// `poi` first, because a shop, hotel or landmark is what tells a rider where
  /// to go and is what a customer expects to see. `address,street` second, so a
  /// pin dropped in open ground still gets a street rather than nothing.
  static const List<String> _reverseTypePasses = ['poi', 'address,street'];

  /// Long enough for a slow connection, short enough that the customer has not
  /// given up and dragged the pin somewhere else before the answer lands.
  static const Duration _requestTimeout = Duration(seconds: 10);

  final http.Client client;
  final String reverseEndpoint;
  final String forwardEndpoint;

  /// Supplies the token per request rather than reading it once at startup, so
  /// a token appearing later (tests, a late `.env` load) is still picked up.
  final String? Function() tokenResolver;

  /// Counts reverse lookups so a slow answer to an abandoned request can be
  /// recognised and thrown away instead of overwriting the name of the newest
  /// pin.
  int _latestReverseRequestId = 0;

  GeocodingService({
    http.Client? client,
    this.reverseEndpoint = _defaultReverseEndpoint,
    this.forwardEndpoint = _defaultForwardEndpoint,
    String? Function()? tokenResolver,
  })  : client = client ?? http.Client(),
        tokenResolver = tokenResolver ?? _mapboxTokenResolver;

  /// Reads the app's public Mapbox token.
  ///
  /// A closure rather than the token itself, so the token is looked up per
  /// request instead of being frozen into this object at construction.
  static String? _mapboxTokenResolver() => MapboxConfig.usableToken;

  /// The name of the place at [lat]/[lng], or null when nothing was found, the
  /// request failed, or this answer arrived after a newer request was started.
  ///
  /// Returns null rather than throwing for every failure — no connection, a
  /// non-200 status, a body that is not the JSON we expect. Naming a place is a
  /// convenience layered on top of a pin that is already good, so there is
  /// nothing for the caller to recover from.
  Future<String?> getPlaceName(double lat, double lng) async {
    // A build with no token, or with a secret one, must not make a request that
    // could only be rejected. `usableToken` is null in both cases.
    final token = tokenResolver();
    if (token == null || token.isEmpty) return null;

    final requestId = ++_latestReverseRequestId;

    for (final types in _reverseTypePasses) {
      // The customer moved on between the two passes. There is no point
      // finishing a lookup whose answer nobody is waiting for.
      if (requestId != _latestReverseRequestId) return null;

      // Longitude is asked for before latitude, as the endpoint takes them.
      final uri = Uri.parse(reverseEndpoint).replace(queryParameters: {
        'longitude': lng.toString(),
        'latitude': lat.toString(),
        'types': types,
        'limit': '1',
        'access_token': token,
      });

      try {
        final response = await client.get(uri).timeout(_requestTimeout);

        // Dropped here rather than shown, so a slow old answer can never
        // become the name of a pin the customer has already moved away from.
        if (requestId != _latestReverseRequestId) return null;

        if (response.statusCode != 200) {
          // 401/403 mean the token is missing, wrong, or not allowed to search;
          // 429 means too many requests. The token is never printed, only the
          // fact that it was rejected.
          debugPrint(
            'Mapbox reverse geocoding returned ${response.statusCode}.',
          );
          return null;
        }

        final label = _readPlaceLabel(response);
        // An empty feature list is not a failure: this pass simply has nothing
        // for this point, so the next one gets its turn.
        if (label != null) return label;
      } catch (error) {
        debugPrint('Mapbox reverse geocoding failed: $error');
        return null;
      }
    }

    return null;
  }

  /// The coordinates of [coordinates] as address text, for the delivery map's
  /// address field.
  ///
  /// The same lookup as [getPlaceName]: one request names the pin and fills the
  /// field, so a gesture that stops on a spot costs one call and not two.
  @override
  Future<String?> lookupAddressText(CapturedCoordinates coordinates) =>
      getPlaceName(coordinates.latitude, coordinates.longitude);

  /// The coordinates an address the customer typed refers to, or null when
  /// nothing matched.
  ///
  /// This only decides which branch is closest. A miss costs the customer a
  /// branch they pick by hand, so every failure is swallowed rather than
  /// surfaced as an error.
  @override
  Future<CapturedCoordinates?> lookupCoordinates(String query) async {
    final token = tokenResolver();
    if (token == null || token.isEmpty) return null;

    final search = query.trim();
    if (search.isEmpty) return null;

    final uri = Uri.parse(forwardEndpoint).replace(queryParameters: {
      'q': search,
      // Only the best match is ever read, so there is no reason to pay for or
      // wait for the four after it.
      'limit': '1',
      'access_token': token,
    });

    try {
      final response = await client.get(uri).timeout(_requestTimeout);
      if (response.statusCode != 200) {
        debugPrint('Mapbox forward geocoding returned ${response.statusCode}.');
        return null;
      }

      return _readCoordinates(response);
    } catch (error) {
      debugPrint('Mapbox forward geocoding failed: $error');
      return null;
    }
  }

  /// The label to show for a reverse result.
  ///
  /// The name leads and the address follows it, so the card reads
  /// "Triple One Hotel, Abbottabad, Pakistan" rather than burying the name at
  /// the end of a line of context. A feature with no name falls back to the
  /// address text on its own, and one with neither is treated as nothing found.
  static String? _readPlaceLabel(http.Response response) {
    final feature = _firstFeature(response);
    if (feature == null) return null;

    final properties = feature['properties'];
    if (properties is! Map<String, dynamic>) return null;

    final name = _readText(properties['name']);
    final address = _readText(properties['full_address']) ??
        _readText(properties['place_formatted']);

    if (name == null) return address;
    if (address == null) return name;
    // Some results repeat themselves — a street whose name *is* its full
    // address — and "Shiekh Dheri Road, Shiekh Dheri Road" helps nobody.
    if (name == address) return name;

    return '$name, $address';
  }

  /// Pulls the point out of a response.
  ///
  /// GeoJSON orders coordinates as `[longitude, latitude]`, so the first number
  /// is *not* the latitude. Getting this backwards drops the customer in the
  /// middle of the ocean, which is why the order is asserted in the tests.
  static CapturedCoordinates? _readCoordinates(http.Response response) {
    final feature = _firstFeature(response);
    if (feature == null) return null;

    final geometry = feature['geometry'];
    if (geometry is! Map<String, dynamic>) return null;

    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.length < 2) return null;

    final longitude = _readNumber(coordinates[0]);
    final latitude = _readNumber(coordinates[1]);
    if (longitude == null || latitude == null) return null;

    return CapturedCoordinates(latitude: latitude, longitude: longitude);
  }

  /// The first feature of a FeatureCollection, or null when there is none.
  ///
  /// Mapbox answers a point it does not recognise with `"features": []`, which
  /// is a normal outcome rather than a failure.
  static Map<String, dynamic>? _firstFeature(http.Response response) {
    final Object? body;
    try {
      // Decoded from bytes so place names outside Latin-1 — which is most of
      // Pakistan's signage — do not throw on the way in.
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      // An error page or a truncated body, not geocoding results.
      return null;
    }

    if (body is! Map<String, dynamic>) return null;

    final features = body['features'];
    if (features is! List || features.isEmpty) return null;

    final firstFeature = features.first;
    return firstFeature is Map<String, dynamic> ? firstFeature : null;
  }

  /// A usable, non-blank string, or null. Never returns whitespace.
  static String? _readText(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// A finite number, or null. NaN would pass a naive cast and poison the
  /// branch comparison downstream.
  static double? _readNumber(Object? value) {
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null || !number.isFinite) return null;
    return number;
  }

  void dispose() => client.close();
}