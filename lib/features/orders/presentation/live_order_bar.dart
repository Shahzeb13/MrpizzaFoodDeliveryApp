import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/shared_components.dart';
import '../models/order_tracking.dart';
import '../providers/live_order_provider.dart';
import '../providers/order_tracking_provider.dart';
import 'live_order_visibility.dart';
import 'order_status_banner.dart';
import 'order_status_copy.dart';
import '../screens/order_tracking_animations.dart';

/// The stack of bottom bars the browse screens sit on.
///
/// Wrapping both bars together rather than positioning them separately is what
/// keeps the live order bar ABOVE the cart bar: `Positioned(bottom: 0)` twice
/// would stack them on top of each other, so the two call sites became one
/// column whose order is the visual order. When neither has anything to show
/// the column collapses to nothing, exactly as it did before.
class LiveOrderBottomBars extends ConsumerWidget {
  const LiveOrderBottomBars({
    super.key,
    required this.onCheckout,
    this.onOpenOrder,
  });

  final VoidCallback onCheckout;

  /// Overrides the default "open the tracking screen" behaviour. Left null on
  /// the browse screens so the bar and the cart bar cannot disagree about what
  /// tapping means.
  final VoidCallback? onOpenOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LiveOrderBar(onOpen: () => _openTrackedOrder(context, ref)),
        CartFloatingBar(onTap: onCheckout),
      ],
    );
  }

  /// Sends the customer to the tracking screen for the order the bar is showing.
  ///
  /// The id is written into [trackedOrderIdProvider] first, and that is not
  /// optional: the tracking screen falls back to "newest order that has not
  /// finished yet", so tapping a cancelled order in the bar without pinning it
  /// would land the customer on a different order entirely.
  void _openTrackedOrder(BuildContext context, WidgetRef ref) {
    final override = onOpenOrder;
    if (override != null) {
      override();
      return;
    }

    final orderId = ref.read(liveOrderIdProvider).valueOrNull;
    if (orderId != null && orderId.isNotEmpty) {
      ref.read(trackedOrderIdProvider.notifier).state = orderId;
    }
    context.push('/orders/track');
  }
}

/// The persistent strip that tells a customer where their food is without them
/// having to go and look.
///
/// This is the whole point of the bar: the live status used to exist only on a
/// screen you had to navigate to from My Orders, by tapping the right order —
/// four taps and a scroll to discover that the branch had cancelled it. An
/// order that is happening to you deserves to be visible while you are doing
/// something else.
class LiveOrderBar extends ConsumerStatefulWidget {
  const LiveOrderBar({super.key, this.onOpen});

  /// Opens the full tracking screen. Fired by tapping anywhere on the bar.
  final VoidCallback? onOpen;

  @override
  ConsumerState<LiveOrderBar> createState() => _LiveOrderBarState();
}

/// `TickerProviderStateMixin`, not the Single variant: there are two controllers
/// here — the one-shot change pulse and the repeating breath.
class _LiveOrderBarState extends ConsumerState<LiveOrderBar>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// One-shot, fired the instant the database moves the order. Sells the change
  /// as an event rather than letting the text quietly swap under the customer.
  late final AnimationController _changePulseController;

  /// Continuous, but only while the order is actually moving. This is the part
  /// that makes the bar read as live at a glance from across the room.
  late final AnimationController _breathController;

  Timer? _deliveredAutoHideTimer;

  /// Which order this widget already wrote a "first seen terminal" record for.
  /// Stops the post-frame write from being queued on every rebuild.
  String? _recordedTerminalFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _changePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deliveredAutoHideTimer?.cancel();
    _changePulseController.dispose();
    _breathController.dispose();
    super.dispose();
  }

  /// Re-checks for orders when the app comes back to the front.
  ///
  /// The realtime socket and the 20s poll both stop while the app is
  /// backgrounded, and the cached "you have nothing active" answer survives
  /// that. Coming back to the app after ordering — on this phone or another
  /// one — has to re-ask the database rather than trust a lookup from before
  /// the customer swiped away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    refreshLiveOrderLookup(ref);
  }

  /// Announces a genuine stage change: a banner plus a kick of motion.
  ///
  /// Only ever called by `OrderStageChangeNotifier`, which deliberately ignores
  /// the first read. Opening the app to discover your order is on its way should
  /// not also fire a banner saying it just started.
  void _announceStageChange(OrderStage stage, OrderTracking tracking) {
    showOrderStatusBanner(context, stage, tracking);
    _changePulseController.forward(from: 0);
  }

  /// Wakes up when the delivered auto-hide deadline arrives, then retires the
  /// order for good.
  ///
  /// The deadline is a pure timestamp comparison, so without this timer nothing
  /// would rebuild at the moment the bar is due to leave and it would sit on
  /// screen indefinitely — the one outcome the timeout exists to prevent.
  ///
  /// Retiring rather than merely hiding is the part that fixes the bug. If the
  /// bar only vanished, the pin would still point at this delivered order and
  /// the bar would be stuck: any later lookup could never adopt anything else.
  /// Recording the conclusion releases the pin and permanently disqualifies the
  /// order, so the bar is free to pick up the next one.
  void _scheduleDeliveredAutoHide(OrderTracking tracking) {
    _deliveredAutoHideTimer?.cancel();

    final shownAt =
        ref.read(liveOrderConclusionsProvider)[tracking.orderId]?.firstShownTerminalAt;
    if (shownAt == null) return;

    final remaining = liveOrderDeliveredAutoHideDelay - DateTime.now().difference(shownAt);
    if (remaining <= Duration.zero) return;

    final orderId = tracking.orderId;
    _deliveredAutoHideTimer = Timer(remaining, () {
      if (!mounted) return;
      dismissLiveOrderConclusion(ref, orderId);
    });
  }

  /// Records the moment the bar first painted a terminal state, after the
  /// frame. Doing it inline would write to a provider during build.
  void _recordTerminalStateOnce(
    OrderTracking tracking,
    LiveOrderVisibility visibility,
  ) {
    final isTerminalOutcome = visibility == LiveOrderVisibility.delivered ||
        visibility == LiveOrderVisibility.cancelled;
    if (!isTerminalOutcome) return;
    if (_recordedTerminalFor == tracking.orderId) return;

    final alreadyRecorded =
        ref.read(liveOrderConclusionsProvider).containsKey(tracking.orderId);
    _recordedTerminalFor = tracking.orderId;
    if (alreadyRecorded) return;

    final orderId = tracking.orderId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      recordLiveOrderFirstShownTerminal(ref, orderId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final trackingAsync = ref.watch(liveOrderTrackingProvider);
    final conclusions = ref.watch(liveOrderConclusionsProvider);

    final tracking = trackingAsync.valueOrNull;
    final visibility = resolveLiveOrderVisibility(
      tracking: tracking,
      isLoading: trackingAsync.isLoading,
      hasError: trackingAsync.hasError,
      conclusion: tracking == null ? null : conclusions[tracking.orderId],
      now: DateTime.now(),
    );

    if (visibility == LiveOrderVisibility.hidden || tracking == null) {
      _deliveredAutoHideTimer?.cancel();
      _recordedTerminalFor = null;
      return const SizedBox.shrink();
    }

    _scheduleDeliveredAutoHide(tracking);
    _recordTerminalStateOnce(tracking, visibility);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, entrance, child) => Opacity(
          opacity: entrance.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - entrance) * 26),
            child: child,
          ),
        ),
        child: _buildBar(context, tracking, visibility),
      ),
    );
  }

  Widget _buildBar(
    BuildContext context,
    OrderTracking tracking,
    LiveOrderVisibility visibility,
  ) {
    final stage = tracking.stage;
    final accent = stageColorFor(stage);

    // Delivered and cancelled are both endings the customer is allowed to
    // clear. Anything still moving is not: an in-flight order is the one thing
    // this bar exists to guarantee is visible, so it has no gesture that makes
    // it go away.
    final isEnding = visibility == LiveOrderVisibility.delivered ||
        visibility == LiveOrderVisibility.cancelled;

    final surface = Semantics(
      container: true,
      liveRegion: true,
      label: '${stageHeadline(stage, tracking)}. ${stageSubtitle(stage, tracking)}',
      button: true,
      child: GestureDetector(
        onTap: widget.onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accent.withValues(alpha: 0.32)),
            boxShadow: const [
              BoxShadow(
                color: AppColors.overlay,
                blurRadius: 26,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Watches for a real status change and fires the banner plus the
              // motion kick. Collapses to nothing, so it costs no layout.
              OrderStageChangeNotifier(
                tracking: tracking,
                onStageChanged: (stage, _) => _announceStageChange(stage, tracking),
              ),
              Row(
                children: [
                  _buildStageBadge(stage, accent, visibility),
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
                            fontSize: 15,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stageSubtitle(stage, tracking),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            color: Colors.white.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w500,
                            fontSize: 11.5,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildBillNumber(tracking),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white54,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 11),
              _buildProgressTrack(stage, accent, visibility),
              if (isEnding) ...[
                const SizedBox(height: 10),
                _buildDismissRow(tracking.orderId),
              ],
            ],
          ),
        ),
      ),
    );

    if (!isEnding) return surface;

    // Swipe-to-clear, offered alongside the Dismiss button rather than instead
    // of it: a delivered order is a bar the customer is done with, and having to
    // aim at a small text button to acknowledge it is friction for something
    // they already agree about. Kept off the active stage on purpose — see
    // [isEnding].
    return Dismissible(
      key: ValueKey<String>('live-order-dismiss-${tracking.orderId}'),
      direction: DismissDirection.horizontal,
      background: _buildDismissBackground(accent),
      onDismissed: (_) => dismissLiveOrderConclusion(ref, tracking.orderId),
      child: surface,
    );
  }

  /// Revealed as the bar is dragged away. Matches the ending's own colour so the
  /// swipe confirms which outcome is being cleared.
  Widget _buildDismissBackground(Color accent) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 28),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Icon(Icons.close_rounded, color: accent, size: 22),
    );
  }

  Widget _buildStageBadge(
    OrderStage stage,
    Color accent,
    LiveOrderVisibility visibility,
  ) {
    // Two motion sources on one icon: a repeating breath that only runs while
    // the order is moving, and a one-shot kick when the stage actually changes.
    // Without the gate the bar would keep twitching at a customer staring at a
    // delivered order, which reads as "something is still happening".
    final isActive = visibility == LiveOrderVisibility.active;
    if (isActive) {
      _breathController.repeat(reverse: true);
    } else if (_breathController.isAnimating) {
      _breathController.stop();
      _breathController.value = 0.5;
    }

    return AnimatedBuilder(
      animation: Listenable.merge([_breathController, _changePulseController]),
      builder: (context, child) {
        final breath = isActive ? 0.94 + (_breathController.value * 0.10) : 1.0;
        final kick = 1.0 + (_changePulseController.value * 0.14);
        return Transform.scale(scale: breath * kick, child: child);
      },
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.45),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(stageIconFor(stage), color: Colors.white, size: 19),
      ),
    );
  }

  Widget _buildBillNumber(OrderTracking tracking) {
    final billNumber = tracking.billNumber;
    // Orders placed before the serial trigger have none. Showing the word
    // "Bill" with nothing after it is worse than showing nothing.
    if (billNumber == null || billNumber.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '#$billNumber',
        style: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          color: Colors.white70,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildProgressTrack(
    OrderStage stage,
    Color accent,
    LiveOrderVisibility visibility,
  ) {
    // A cancelled order never completed any step, so filling by pipeline
    // progress would draw an empty track — indistinguishable from "we have not
    // started yet". Filling it solid in the danger colour says "this ended".
    final fraction = visibility == LiveOrderVisibility.cancelled
        ? 1.0
        : pipelineProgressFor(stage) / OrderTracking.pipelineStepCount;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fraction),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 4,
          backgroundColor: Colors.white.withValues(alpha: 0.12),
          valueColor: AlwaysStoppedAnimation<Color>(accent),
        ),
      ),
    );
  }

  Widget _buildDismissRow(String orderId) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => dismissLiveOrderConclusion(ref, orderId),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white70,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Dismiss',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }
}
