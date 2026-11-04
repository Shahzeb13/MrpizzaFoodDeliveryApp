import 'package:flutter/material.dart';

/// Comprehensive brand colors for Mr. Pizza.
///
/// Warm editorial palette — charred tomato brick as the single action accent,
/// warm ivory surfaces, espresso ink, and a supporting honey gold reserved for
/// special-offer chips and the logo ring only.
abstract final class AppColors {
  // Brand Accent (Vibrant Red matching reference UI)
  static const Color primary = Color(0xFFE51926);      // Vibrant Primary Red
  static const Color primaryDark = Color(0xFFB8101C);  // Deep Red
  static const Color primaryLight = Color(0xFFFF3B47); // Coral Red

  // Brand Tints (Soft, low-saturation surfaces derived from the accent)
  static const Color primaryTint = Color(0xFFFFECEE);  // Soft Pinkish Blush
  static const Color primaryTintDeep = Color(0xFFFFD4D8);

  // Supporting Highlight (Honey Gold — offers, logo ring, stars gradient)
  static const Color accent = Color(0xFFE3A63B);
  static const Color accentYellow = Color(0xFFE3A63B);
  static const Color goldTint = Color(0xFFFDF0DC);

  // Semantic Status
  static const Color success = Color(0xFF2F7D4F);     // Warm Leaf Green
  static const Color warning = Color(0xFFC0691F);     // Spiced Orange

  // Bad news. Deliberately deeper and less orange than [primary] so a cancelled
  // order is never mistaken for the brand's normal action colour.
  static const Color danger = Color(0xFF8E1F2A);     // Deep Crimson

  // Backgrounds & Surfaces (Soft Neumorphic Canvas)
  static const Color background = Color(0xFFF0F3F8);  // Soft Neumorphic Slate Canvas
  static const Color surface = Color(0xFFF0F3F8);     // Surface matches canvas for soft dual-shadow
  static const Color surfacePure = Color(0xFFFFFFFF); // Crisp White
  static const Color sand = Color(0xFFE5EBF3);        // Debossed well
  static const Color sandDeep = Color(0xFFD8E1ED);    // Deep Debossed fill
  static const Color surfaceDark = Color(0xFF241A12); // Espresso
  static const Color cardBg = Color(0xFFFFFFFF);

  // Neutral Text & Icons (Warm, never pure gray-black)
  static const Color textPrimary = Color(0xFF241A12);   // Espresso Ink
  static const Color textSecondary = Color(0xFF83725F); // Warm Stone
  static const Color textLight = Color(0xFFB8A793);     // Muted Tan

  // Hairlines & Shadows (Tinted warm — replaces flat gray borders)
  static const Color border = Color(0xFFEFE3D4);
  static const Color borderDeep = Color(0xFFE0CFB8);

  // Shadows & Overlays
  static const Color shadow = Color(0x22614A30);     // Warm brown haze
  static const Color shadowSoft = Color(0x0F614A30); // Whisper soft
  static const Color overlay = Color(0x66342B22);    // Warm dim
  static const Color bannerScrim = Color(0xCC1F1710); // Deep warm scrim
}