import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/router.dart';
import 'core/theme/app_theme.dart';

/// Root application widget.
///
/// This stage wires up Riverpod state management and go_router navigation.
/// No backend, auth, or native plugins are included yet.
class MrPizzaApp extends StatelessWidget {
  const MrPizzaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp.router(
        title: 'MrPizza',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: router,
      ),
    );
  }
}