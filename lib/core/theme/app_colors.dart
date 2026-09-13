import 'package:flutter/material.dart';

/// Comprehensive brand colors for Mr. Pizza.
/// Styled after competitor's ultra-clean, minimalist aesthetic: Vibrant Red, Yellow Action Accents, Crisp White.
abstract final class AppColors {
  // Primary Palette (Soft Matte Brand Red - Eye Pleasing)
  static const Color primary = Color(0xFFC82323);      // Soft Matte Brand Red
  static const Color primaryDark = Color(0xFFA91D1D);  // Warm Dark Crimson
  static const Color primaryLight = Color(0xFFE54343); // Soft Light Red
  
  // Secondary / Action Accent Palette (Yellow + Badge Gold)
  static const Color accent = Color(0xFFFFD500);       // Bright Yellow (Action Buttons)
  static const Color accentYellow = Color(0xFFFFC107); // Warm Yellow
  static const Color success = Color(0xFF2E7D32);      // Fresh Green
  static const Color warning = Color(0xFFE65100);      // Orange
  
  // Backgrounds & Surfaces
  static const Color background = Color(0xFFF7F7F7);   // Ultra Clean Soft Off-White
  static const Color surface = Color(0xFFFFFFFF);      // Pure Crisp White
  static const Color surfaceDark = Color(0xFF1E1B18);  // Charcoal
  static const Color cardBg = Color(0xFFFFFFFF);
  
  // Neutral Text & Icons
  static const Color textPrimary = Color(0xFF1F1F1F);   // Rich Black Text
  static const Color textSecondary = Color(0xFF757575); // Clean Muted Gray
  static const Color textLight = Color(0xFF9E9E9E);     // Light Gray
  static const Color border = Color(0xFFEEEEEE);        // Subtle Light Border
  
  // Shadows & Overlays
  static final Color shadow = const Color(0xFF000000).withOpacity(0.06);
  static final Color overlay = const Color(0xFF000000).withOpacity(0.40);
}