import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app.dart';
import 'core/config/mapbox_config.dart';
import 'features/notifications/services/notification_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Hot Restart re-executes main() from scratch but the Supabase singleton
  // persists in memory, so a second initialize() call throws. We catch that
  // so the restart skips the blocking network round-trip entirely.
  try {
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
  } catch (_) {
    // Already initialized (Hot Restart) — safe to continue.
  }

  await NotificationService.instance.initialize();

  _installMapboxAccessToken();

  runApp(const MrPizzaApp());
}

/// Hands the Mapbox SDK the public access token before any widget can create a
/// map.
///
/// The token has to be set on the native SDK at startup — Flutter's `.env`
/// loader only fills Dart-side values, so nothing about Mapbox is configured by
/// reading the file. A build with no token, or with a secret `sk.` token, is
/// left unconfigured on purpose: the location picker then shows a plain
/// "map unavailable" panel and the customer types their address instead, rather
/// than the app failing to start.
void _installMapboxAccessToken() {
  MapboxConfig.logConfigurationStatus();

  final token = MapboxConfig.usableToken;
  if (token == null) return;

  MapboxOptions.setAccessToken(token);
}
