import 'package:flutter/material.dart';

import 'app_colors.dart';

/// App-wide theme.
///
/// Basic Material 3 theme seeded from the MrPizza brand color.
abstract final class AppTheme {
  static ThemeData get light {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
      useMaterial3: true,
    );
  }
}