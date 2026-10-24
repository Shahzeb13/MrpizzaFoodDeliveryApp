import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Resolves the Mapbox **public** access token the delivery map runs on.
///
/// The token is read from two places, in this order:
///
/// 1. `--dart-define=MAPBOX_ACCESS_TOKEN=pk...` — baked in at compile time,
///    which is what CI and release builds use.
/// 2. `MAPBOX_ACCESS_TOKEN` in `.env` — read at runtime by `flutter_dotenv`,
///    which is what local development uses. `.env` is gitignored and is never
///    committed (see `.env.example` for the key name).
///
/// The token is deliberately never logged and never falls back to a compiled-in
/// default: an app that cannot find a token still starts, and the location
/// picker shows a plain "map unavailable" state instead of throwing during
/// `runApp`.
abstract final class MapboxConfig {
  MapboxConfig._();

  /// The single variable name the token is read from, whichever source supplies
  /// it.
  static const String tokenKey = 'MAPBOX_ACCESS_TOKEN';

  /// Read once, before `runApp`, so the map never initialises against a
  /// half-configured value.
  static String? _resolvedToken;

  /// Resolves the token, preferring the compile-time `--dart-define` value.
  ///
  /// Safe to call more than once; only the first call does any work.
  static String? initialise() {
    if (_resolvedToken != null) return _resolvedToken;
    return _resolvedToken = _readToken();
  }

  /// The token the SDK should run on, or null when none is configured.
  ///
  /// Never log this value.
  static String? get accessToken => initialise();

  /// True when the app has a token the map can actually start with.
  static bool get isConfigured => (accessToken ?? '').trim().isNotEmpty;

  /// True when the configured value is a Mapbox **secret** token.
  ///
  /// Secret tokens start with `sk.` and grant read/write access to the whole
  /// Mapbox account. The Maps SDK must never be handed one, and a token that
  /// leaked into a mobile binary cannot be un-leaked — so a value like that is
  /// refused here, in Dart, before the native SDK sees it.
  static bool get holdsSecretToken {
    final token = accessToken?.trim() ?? '';
    return token.startsWith('sk.');
  }

  /// True when the map can run: a token exists and it is a public one.
  static bool get isUsable => isConfigured && !holdsSecretToken;

  /// The token to hand to `MapboxOptions.setAccessToken`, or null when the map
  /// must not start.
  ///
  /// A secret token returns null rather than being passed through, so a
  /// misconfigured build degrades to the "map unavailable" state instead of
  /// shipping account access to every customer.
  static String? get usableToken => isUsable ? accessToken!.trim() : null;

  /// Customer-facing explanation for a map that cannot start.
  ///
  /// Deliberately says nothing about tokens or configuration: this is shown to
  /// customers, not to developers.
  static const String unavailableMessage =
      'The map is unavailable right now. You can still choose a saved address '
      'or type your delivery address below.';

  static String? _readToken() {
    // Compile-time first: an explicit --dart-define beats an ambient .env.
    const compiled = String.fromEnvironment(tokenKey);
    if (compiled.trim().isNotEmpty) return compiled.trim();

    // `dotenv.env` throws when .env was never loaded, which is the case in
    // widget tests and in any entry point other than main().
    if (dotenv.isInitialized) {
      final fromFile = dotenv.maybeGet(tokenKey);
      if (fromFile != null && fromFile.trim().isNotEmpty) {
        return fromFile.trim();
      }
    }

    return null;
  }

  /// Debug-only statement that says *whether* a token was found, never what it
  /// is. Reports the shape of the problem instead of the secret.
  static String describeConfiguration() {
    if (accessToken == null) {
      return 'Mapbox: no $tokenKey found. Pass it with '
          '--dart-define=$tokenKey=pk... or put it in .env.';
    }
    if (holdsSecretToken) {
      return 'Mapbox: $tokenKey holds a SECRET (sk.) token. The mobile app '
          'must use a public pk. token — the map will stay unavailable.';
    }
    return 'Mapbox: public $tokenKey found.';
  }

  /// Logs [describeConfiguration] in debug builds only.
  static void logConfigurationStatus() {
    if (kDebugMode) {
      debugPrint(describeConfiguration());
    }
  }
}
