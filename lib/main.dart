import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

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

  runApp(const MrPizzaApp());
}
