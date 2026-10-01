import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../models/order_tracking.dart';
import 'order_status_copy.dart';

/// Tells the customer their order just moved, from anywhere in the app.
///
/// This is the ambient half of the live order bar. The bar itself is a quiet
/// strip at the bottom of the screen; a customer who scrolled past it while
/// deciding on a dessert would never know their food left the pass, so the
/// moment a stage actually changes this drops a banner from the top.
///
/// Top rather than bottom on purpose: the bottom of the screen belongs to the
/// live order bar and the cart bar, and a banner landing there would cover the
/// status it is announcing. Top also matches the existing cart toast
/// (`showTopCartToast`), so the app has one place transient messages come from.
///
/// Fires only on a genuine change, never on first load — the bar's caller is
/// responsible for that, using `OrderStageChangeNotifier`.
///
/// Coloured by [stageColorFor] rather than a fixed success green, which is what
/// used to announce cancellations as good news.
void showOrderStatusBanner(
  BuildContext context,
  OrderStage stage,
  OrderTracking tracking,
) {
  final overlay = Overlay.maybeOf(context);
  // No overlay means no navigator to attach to. There is nothing useful to do
  // about that and nothing worth crashing a home screen over.
  if (overlay == null) return;

  final accent = stageColorFor(stage);
  late final OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            builder: (context, value, child) => Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - value) * -24),
                child: child,
              ),
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceDark,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.overlay,
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        stageIconFor(stage),
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            stageHeadline(stage, tracking),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            stageSubtitle(stage, tracking),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              color: Colors.white.withValues(alpha: 0.72),
                              fontWeight: FontWeight.w500,
                              fontSize: 11.5,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);

  // Long enough to read both lines, short enough that a customer who has moved
  // on is not blocked by a stale banner. The entry removes itself; a customer
  // who swiped to another route still sees it land, because an overlay entry
  // outlives the widget that inserted it.
  Future.delayed(const Duration(milliseconds: 4200), () {
    if (entry.mounted) entry.remove();
  });
}
