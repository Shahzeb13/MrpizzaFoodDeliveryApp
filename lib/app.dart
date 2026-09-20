import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/auth_gate.dart';

/// Root application widget.
///
/// Wires up Riverpod state management. [AuthGate] owns the startup session
/// check and auth-driven navigation (Supabase-backed).
class MrPizzaApp extends StatelessWidget {
  const MrPizzaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(
      child: AuthGate(),
    );
  }
}
