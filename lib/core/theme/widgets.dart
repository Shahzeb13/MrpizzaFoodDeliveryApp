/// Theme-aware shared widgets for Mr. Pizza.
///
/// Small, opinionated primitives used across screens: the double-bezel shell,
/// section titles, eyebrow chips and price text.
library;

import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_theme.dart';

/// Soft white card — elevation expressed with a warm tinted shadow instead of
/// a flat gray border. The standard surface for lists and forms.
class MrCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final BorderRadius? borderRadius;
  final Color? color;
  final VoidCallback? onTap;

  const MrCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.borderRadius,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(20);
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSoft,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return Container(margin: margin, child: content);
    return Container(
      margin: margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: content,
        ),
      ),
    );
  }
}

/// The "double-bezel" nested shell. An outer sand tray with a hairline ring
/// cradles an inner content core — the app's premium hero / balance surfaces.
class MrDoubleBezel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry outerPadding;
  final EdgeInsetsGeometry innerPadding;
  final double radius;
  final Color? trayColor;
  final Color? innerColor;

  const MrDoubleBezel({
    super.key,
    required this.child,
    this.outerPadding = const EdgeInsets.all(6),
    this.innerPadding = const EdgeInsets.all(20),
    this.radius = 26,
    this.trayColor,
    this.innerColor,
  });

  @override
  Widget build(BuildContext context) {
    final outerRounded = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        color: trayColor ?? AppColors.sand,
        borderRadius: outerRounded,
        border: Border.all(color: AppColors.borderDeep),
      ),
      padding: outerPadding,
      child: Container(
        width: double.infinity,
        padding: innerPadding,
        decoration: BoxDecoration(
          color: innerColor ?? AppColors.surface,
          borderRadius: BorderRadius.circular(radius - outerPadding.vertical),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowSoft,
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Section heading with an always-descending micro-label on top.
class MrSectionTitle extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final Widget? trailing;

  const MrSectionTitle({
    super.key,
    required this.title,
    this.eyebrow,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          MrEyebrow(text: eyebrow!),
          const SizedBox(height: 4),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(title, style: theme.textTheme.headlineSmall),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ],
    );
  }
}

/// Microscopic pill badge used above major headings.
class MrEyebrow extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;

  const MrEyebrow({
    super.key,
    required this.text,
    this.background = AppColors.goldTint,
    this.foreground = const Color(0xFF9A6B1F),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

/// Price text — bold with tabular figures so digits align.
class MrPriceText extends StatelessWidget {
  final num amount;
  final double fontSize;
  final Color? color;
  final bool rupees;

  const MrPriceText(
    this.amount, {
    super.key,
    this.fontSize = 15,
    this.color,
    this.rupees = true,
  });

  @override
  Widget build(BuildContext context) {
    final effective = color ?? AppColors.primary;
    final whole = amount.toInt();
    return Text(
      rupees ? 'Rs. $whole' : '$whole',
      style: TextStyle(
        fontFamily: AppTheme.fontFamily,
        color: effective,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Rounded tinted icon well — the consistent icon treatment app-wide.
class MrIconWell extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final Color? background;

  const MrIconWell({
    super.key,
    required this.icon,
    this.color = AppColors.primary,
    this.size = 20,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background ?? AppColors.primaryTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color, size: size),
    );
  }
}

/// Hairline that fades out at the edges for a softer break between sections.
class MrFadeDivider extends StatelessWidget {
  const MrFadeDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            AppColors.border.withValues(alpha: 0.85),
            Colors.transparent,
          ],
          stops: const [0, 0.5, 1],
        ),
      ),
    );
  }
}