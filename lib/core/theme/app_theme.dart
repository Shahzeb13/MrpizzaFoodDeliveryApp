import 'package:flutter/material.dart';
import 'app_colors.dart';

/// App-wide theme definition for Mr. Pizza.
///
/// Single premium design language:
/// - Plus Jakarta Sans throughout (bundled).
/// - Warm ivory canvas, espresso ink, one charred-brick accent.
/// - Pill CTAs with a nested trailing icon well, soft warm shadows, hairline
///   warm borders instead of flat gray hacks.
abstract final class AppTheme {
  static const String fontFamily = 'PlusJakartaSans';

  static ThemeData get light {
    const colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryTint,
      onPrimaryContainer: AppColors.primaryDark,
      secondary: AppColors.accent,
      onSecondary: AppColors.textPrimary,
      secondaryContainer: AppColors.goldTint,
      onSecondaryContainer: AppColors.textPrimary,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainer: AppColors.sand,
      onSurfaceVariant: AppColors.textSecondary,
      error: Color(0xFFB3261E),
      onError: Colors.white,
      outline: AppColors.borderDeep,
      outlineVariant: AppColors.border,
    );

    const base = TextStyle(
      fontFamily: fontFamily,
      color: AppColors.textPrimary,
      height: 1.4,
    );

    final textTheme = TextTheme(
      // Massive display — used sparingly on splash / onboarding
      displayLarge: base.copyWith(
        fontSize: 52, fontWeight: FontWeight.w800, height: 1.02,
        letterSpacing: -1.4,
      ),
      displayMedium: base.copyWith(
        fontSize: 40, fontWeight: FontWeight.w800, height: 1.05,
        letterSpacing: -1.1,
      ),
      displaySmall: base.copyWith(
        fontSize: 32, fontWeight: FontWeight.w800, height: 1.1,
        letterSpacing: -0.9,
      ),
      // Headlines — bold, tight, intentional
      headlineLarge: base.copyWith(
        fontSize: 28, fontWeight: FontWeight.w800, height: 1.12,
        letterSpacing: -0.7,
      ),
      headlineMedium: base.copyWith(
        fontSize: 23, fontWeight: FontWeight.w800, height: 1.15,
        letterSpacing: -0.5,
      ),
      headlineSmall: base.copyWith(
        fontSize: 20, fontWeight: FontWeight.w800, height: 1.2,
        letterSpacing: -0.4,
      ),
      // Titles
      titleLarge: base.copyWith(
        fontSize: 18, fontWeight: FontWeight.w700, height: 1.25,
        letterSpacing: -0.3,
      ),
      titleMedium: base.copyWith(
        fontSize: 16, fontWeight: FontWeight.w700, height: 1.3,
        letterSpacing: -0.2,
      ),
      titleSmall: base.copyWith(
        fontSize: 14, fontWeight: FontWeight.w700, height: 1.3,
        letterSpacing: -0.1,
      ),
      // Body
      bodyLarge: base.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
      bodyMedium: base.copyWith(
        fontSize: 14, fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      bodySmall: base.copyWith(
        fontSize: 12, fontWeight: FontWeight.w500, height: 1.45,
        letterSpacing: 0.05, color: AppColors.textSecondary,
      ),
      // Labels — micro typography with optical-size tracking
      labelLarge: base.copyWith(
        fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2,
      ),
      labelMedium: base.copyWith(
        fontSize: 12, fontWeight: FontWeight.w700,
        letterSpacing: 0.2, color: AppColors.textSecondary,
      ),
      labelSmall: base.copyWith(
        fontSize: 11, fontWeight: FontWeight.w700,
        letterSpacing: 0.5, color: AppColors.textSecondary,
      ),
    );

    final pillShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(56),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: colorScheme,
      splashFactory: InkRipple.splashFactory,
      splashColor: AppColors.primary.withValues(alpha: 0.06),
      highlightColor: AppColors.primary.withValues(alpha: 0.04),

      textTheme: textTheme,

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
      ),

      cardTheme: CardThemeData(
        color: AppColors.cardBg,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          disabledBackgroundColor: AppColors.sandDeep,
          disabledForegroundColor: AppColors.textLight,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: pillShape,
          textStyle: textTheme.labelLarge?.copyWith(color: Colors.white),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.borderDeep),
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: pillShape,
          textStyle: textTheme.labelLarge?.copyWith(color: AppColors.primary),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: textTheme.labelLarge,
          shape: pillShape,
          overlayColor: AppColors.primary.withValues(alpha: 0.06),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.textLight,
          fontWeight: FontWeight.w500,
        ),
        labelStyle: textTheme.labelMedium,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        floatingLabelStyle:
            const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
        prefixIconColor: AppColors.primary,
        suffixIconColor: AppColors.textLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFB3261E)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFB3261E), width: 1.6),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.sand,
        selectedColor: AppColors.primary,
        disabledColor: AppColors.sand,
        labelStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          fontFamily: fontFamily,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide.none,
        ),
        checkmarkColor: Colors.white,
        showCheckmark: false,
        brightness: Brightness.light,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceDark,
        contentTextStyle: const TextStyle(
          fontFamily: fontFamily,
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0x33FFFFFF)),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: 0,
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.textSecondary,
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.border),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        dividerColor: Colors.transparent,
        labelStyle: textTheme.labelLarge?.copyWith(
          color: AppColors.primary,
          letterSpacing: -0.1,
        ),
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(
          color: AppColors.textSecondary,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.sandDeep,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),

      radioTheme: const RadioThemeData(
        fillColor: WidgetStatePropertyAll(AppColors.primary),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.sandDeep,
        linearMinHeight: 3,
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
      ),

      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      dividerColor: AppColors.border,
    );
  }
}