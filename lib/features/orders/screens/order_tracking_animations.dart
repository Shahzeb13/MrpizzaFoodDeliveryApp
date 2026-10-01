import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../models/order_tracking.dart';
import '../presentation/order_status_copy.dart';

/// Watches the tracked order and reports when the database moves it along.
///
/// The order is driven by a branch dashboard on another machine, so a change
/// arrives with no user action at all. This listener exists so the screen can
/// acknowledge that: an animation the moment the stage changes, and a banner
/// that says what just happened, instead of the new text silently replacing the
/// old one while the customer happens to be looking at something else.
class OrderStageChangeNotifier extends ConsumerStatefulWidget {
  const OrderStageChangeNotifier({
    super.key,
    required this.tracking,
    required this.onStageChanged,
  });

  final OrderTracking? tracking;
  final void Function(OrderStage stage, String status) onStageChanged;

  @override
  ConsumerState<OrderStageChangeNotifier> createState() =>
      _OrderStageChangeNotifierState();
}

class _OrderStageChangeNotifierState
    extends ConsumerState<OrderStageChangeNotifier> {
  String? _lastStatus;

  @override
  Widget build(BuildContext context) {
    final tracking = widget.tracking;
    if (tracking != null) {
      final status = tracking.status;
      if (_lastStatus == null) {
        // The first read is not a change — it is simply the state we started
        // in, and announcing it would fire a banner the moment the screen
        // opens.
        _lastStatus = status;
      } else if (_lastStatus != status) {
        _lastStatus = status;
        // Deferred: this runs during build, and the animation belongs to the
        // tree that is being built.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.onStageChanged(tracking.stage, status);
        });
      }
    }

    return const SizedBox.shrink();
  }
}

/// The header card: the real bill number, the real stage, and the time the
/// order was actually placed.
///
/// The headline is swapped with a slide-and-fade rather than cut, and the whole
/// card lifts briefly when the stage changes. That is the difference between a
/// screen that updates and a screen that reacts — on a delivery order the
/// customer is usually looking at this card waiting for it to change.
class AnimatedOrderStatusHeader extends StatefulWidget {
  const AnimatedOrderStatusHeader({
    super.key,
    required this.tracking,
    required this.pulseKey,
  });

  final OrderTracking tracking;

  /// Changes whenever the order moves, to replay the highlight.
  final Object pulseKey;

  @override
  State<AnimatedOrderStatusHeader> createState() =>
      _AnimatedOrderStatusHeaderState();
}

class _AnimatedOrderStatusHeaderState extends State<AnimatedOrderStatusHeader>
    with SingleTickerProviderStateMixin {
  /// Built eagerly in [initState] rather than as a `late final` with an
  /// initialiser. A lazily-built controller can be constructed on its first
  /// access, and if that first access lands while the element is deactivating —
  /// which is what happens when the order changes stage mid-frame — the ticker
  /// looks up an ancestor that is already gone and throws.
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedOrderStatusHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulseKey != widget.pulseKey) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracking = widget.tracking;
    final stage = tracking.stage;
    final placedAt = tracking.createdAt;

    final curve = CurvedAnimation(
      parent: _pulse,
      curve: Curves.easeOutCubic,
    );

    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) {
        // Dips slightly and comes back, so the card reads as a beat rather
        // than a jump.
        final lift = (curve.value - 1).abs() * 6;
        return Transform.translate(offset: Offset(0, lift), child: child);
      },
      child: MrDoubleBezelShell(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tracking.billNumber ?? 'Order ${tracking.orderId}',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        fontFamily: AppTheme.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 420),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.35),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Column(
                        key: ValueKey<String>('${stage.name}-${tracking.status}'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stageHeadline(stage, tracking),
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            stageSubtitle(stage, tracking),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textLight),
                          ),
                        ],
                      ),
                    ),
                    if (tracking.hasUnrecognisedStatus) ...[
                      const SizedBox(height: 8),
                      // Better to show the raw value than to place a status we
                      // do not understand at the wrong point in the pipeline.
                      Text(
                        'Status: ${tracking.status}',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: AppTheme.fontFamily,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'PLACED',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      fontFamily: AppTheme.fontFamily,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    placedAt == null ? '--' : formatClockTime(placedAt),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                      fontFamily: AppTheme.fontFamily,
                    ),
                  ),
                  if (placedAt != null)
                    Text(
                      formatDayLabel(placedAt),
                      style: const TextStyle(
                        color: AppColors.textLight,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppTheme.fontFamily,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dark rounded card the status header sits in, extracted so the animation
/// wrapper can hold a stable child and not rebuild it on every frame.
class MrDoubleBezelShell extends StatelessWidget {
  const MrDoubleBezelShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.sand,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(23),
        ),
        child: child,
      ),
    );
  }
}

/// A banner that slides in when the branch changes the order.
///
/// Real delivery apps do exactly this: the customer gets told what just
/// happened instead of having to notice it. It only appears for a genuine
/// change, never on first load, and it stays until the next change replaces it
/// — a banner that times out after a few seconds is a banner a customer misses
/// while they were putting their phone down.
class OrderUpdateBanner extends StatelessWidget {
  const OrderUpdateBanner({super.key, required this.stage, required this.message});

  /// Drives the banner's colour and icon. Was a hardcoded success green, which
  /// meant "Order Cancelled" arrived in the exact colour the app uses for good
  /// news — the one update a customer must be unable to glance past.
  final OrderStage stage;

  final String message;

  @override
  Widget build(BuildContext context) {
    final accent = stageColorFor(stage);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - value) * -18),
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.3),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(stageIconFor(stage), color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A ring that breathes behind the current pipeline step.
///
/// The motion is what tells a customer the order is live and something is
/// happening to it right now, rather than the screen having quietly given up.
class PulsingStepRing extends StatefulWidget {
  const PulsingStepRing({
    super.key,
    required this.active,
    required this.color,
    required this.child,
  });

  final bool active;
  final Color color;
  final Widget child;

  @override
  State<PulsingStepRing> createState() => _PulsingStepRingState();
}

class _PulsingStepRingState extends State<PulsingStepRing>
    with SingleTickerProviderStateMixin {
  /// Eager for the same reason as the header's controller: one pipeline step
  /// becomes current at a time, and the step that stops being current is
  /// rebuilt exactly as the previous one tears down.
  late final AnimationController _breathe;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.active) _breathe.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant PulsingStepRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_breathe.isAnimating) {
      _breathe.repeat(reverse: true);
    } else if (!widget.active && _breathe.isAnimating) {
      _breathe.stop();
      _breathe.value = 0;
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;

    return AnimatedBuilder(
      animation: _breathe,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_breathe.value);
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.18 + (0.22 * t)),
                blurRadius: 6 + (10 * t),
                spreadRadius: 1 + (5 * t),
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// The connector between two pipeline steps, which fills as the order advances.
class AnimatedStepConnector extends StatelessWidget {
  const AnimatedStepConnector({
    super.key,
    required this.filled,
    required this.isLast,
  });

  final bool filled;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    if (isLast) return const SizedBox.shrink();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: filled ? 1 : 0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => SizedBox(
        height: 36,
        width: 2,
        child: Align(
          alignment: Alignment.topCenter,
          child: FractionallySizedBox(
            heightFactor: value,
            child: Container(
              color: AppColors.success.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// Convenience for the screen: the id of the order whose stage we are watching.
String trackingPulseKey(OrderTracking tracking) =>
    '${tracking.orderId}:${tracking.status}:${tracking.rider?.assignmentStatus ?? ''}';
