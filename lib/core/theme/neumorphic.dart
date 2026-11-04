import 'package:flutter/material.dart';

/// Reusable Neumorphic (Soft-UI) widgets matching the Mr. Pizza design references.
///
/// Features dual-shadow elevation (soft highlight at top-left, soft slate shadow
/// at bottom-right), inset debossed styling for inputs/wells, and vibrant red CTAs.

class NeuColors {
  static const Color background = Color(0xFFF0F3F8);
  static const Color surface = Color(0xFFF0F3F8);
  static const Color lightShadow = Color(0xFFFFFFFF);
  static const Color darkShadow = Color(0x33A6B4C9);
  static const Color insetBg = Color(0xFFE5EBF3);
  static const Color sand = Color(0xFFE5EBF3);
  static const Color primary = Color(0xFFE51926);
  static const Color primaryGlow = Color(0x4DE51926);
  static const Color accent = Color(0xFFE3A63B);
  static const Color textDark = Color(0xFF141923);
  static const Color textPrimary = Color(0xFF141923);
  static const Color textMuted = Color(0xFF758295);
  static const Color textSecondary = Color(0xFF758295);
  static const Color textSub = Color(0xFF5A6679);
}

/// Standard Neumorphic Raised Card with dual soft shadows.
class NeuCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final dynamic borderRadius;
  final Color? color;
  final VoidCallback? onTap;
  final double blurRadius;
  final Offset offset;

  const NeuCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.borderRadius = 22.0,
    this.color,
    this.onTap,
    this.blurRadius = 14.0,
    this.offset = const Offset(5, 5),
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? NeuColors.surface;
    final r = borderRadius is BorderRadiusGeometry
        ? (borderRadius as BorderRadiusGeometry)
        : BorderRadius.circular((borderRadius as num).toDouble());

    Widget card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: NeuColors.lightShadow,
            offset: -offset,
            blurRadius: blurRadius,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: NeuColors.darkShadow,
            offset: offset,
            blurRadius: blurRadius,
            spreadRadius: 0,
          ),
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      );
    }
    return card;
  }
}

/// Inset / Debossed container for input fields, wells, or active state pills.
class NeuInset extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final dynamic borderRadius;
  final Color? color;
  final double? height;
  final double? width;

  const NeuInset({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.margin = EdgeInsets.zero,
    this.borderRadius = 18.0,
    this.color,
    this.height,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final r = borderRadius is BorderRadiusGeometry
        ? (borderRadius as BorderRadiusGeometry)
        : BorderRadius.circular((borderRadius as num).toDouble());

    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? NeuColors.insetBg,
        borderRadius: r,
        boxShadow: [
          // Inner-shadow simulated with top-left dark bevel and bottom-right light glow
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            offset: const Offset(2, 2),
            blurRadius: 4,
          ),
          const BoxShadow(
            color: Colors.white,
            offset: Offset(-2, -2),
            blurRadius: 4,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Circular Neumorphic Button (e.g. Hamburger menu, Search, Back, Heart icon, Socials).
class NeuCircleButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onPressed;
  final double size;
  final Color? backgroundColor;
  final Color? iconColor;

  const NeuCircleButton({
    super.key,
    required this.child,
    this.onTap,
    this.onPressed,
    this.size = 46.0,
    this.backgroundColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final callback = onPressed ?? onTap;
    return GestureDetector(
      onTap: callback,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor ?? NeuColors.surface,
          boxShadow: const [
            BoxShadow(
              color: NeuColors.lightShadow,
              offset: Offset(-4, -4),
              blurRadius: 9,
            ),
            BoxShadow(
              color: NeuColors.darkShadow,
              offset: Offset(4, 4),
              blurRadius: 9,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// Primary Red Pill Action Button with forward arrow and glow.
class NeuPrimaryButton extends StatelessWidget {
  final String? label;
  final Widget? child;
  final VoidCallback? onPressed;
  final bool showArrow;
  final bool isLoading;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const NeuPrimaryButton({
    super.key,
    this.label,
    this.child,
    this.onPressed,
    this.showArrow = true,
    this.isLoading = false,
    this.height = 54.0,
    this.borderRadius = 28.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          color: NeuColors.primary,
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: NeuColors.primaryGlow,
              offset: const Offset(0, 8),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : child ??
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label ?? '',
                      style: const TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (showArrow) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                    ],
                  ],
                ),
      ),
    );
  }
}

/// Status / Tag Pills (e.g. WELCOME, PIZZA FLAVOURS, DELIVERED, DECLINED).
class NeuPillBadge extends StatelessWidget {
  final String label;
  final Color? textColor;
  final Color? backgroundColor;
  final bool isInset;

  const NeuPillBadge({
    super.key,
    required this.label,
    this.textColor,
    this.backgroundColor,
    this.isInset = false,
  });

  @override
  Widget build(BuildContext context) {
    final tColor = textColor ?? NeuColors.primary;
    if (isInset) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: backgroundColor ?? NeuColors.insetBg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: tColor,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontFamily: 'PlusJakartaSans',
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: tColor,
        ),
      ),
    );
  }
}
