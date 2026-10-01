import '../models/order_tracking.dart';

/// How long a finished delivery keeps its place on the home bar.
///
/// A delivered order that vanished the instant it was delivered feels broken —
/// the customer cannot tell "it worked" from "it fell off". So the result stays
/// long enough to register, then gets out of the way on its own. A cancellation
/// deliberately does NOT use this: it needs the customer to acknowledge it, not
/// to have it quietly time out.
const Duration liveOrderDeliveredAutoHideDelay = Duration(seconds: 60);

/// What the persistent home/menu bar should be showing, if anything.
enum LiveOrderVisibility {
  /// Nothing to show. Either the customer has no order, the read failed, or
  /// they have already seen and dismissed the result.
  hidden,

  /// The order is still moving through the kitchen or out with a rider.
  active,

  /// Delivered, shown for [liveOrderDeliveredAutoHideDelay] and then gone.
  delivered,

  /// Cancelled. Stays until the customer dismisses it.
  cancelled,
}

/// What the customer has already been shown about a finished order.
///
/// Recorded rather than recomputed, because both terminal rules need a memory:
/// "how long ago did this finish" for delivery, and "has the customer actually
/// seen it" for cancellation.
class LiveOrderConclusion {
  /// When the bar first rendered this order in a terminal state. Null only for
  /// a conclusion written by an explicit dismissal before the bar ever painted.
  final DateTime? firstShownTerminalAt;

  /// When the customer tapped Dismiss. Null while it is still waiting to be
  /// acknowledged.
  final DateTime? dismissedAt;

  const LiveOrderConclusion({this.firstShownTerminalAt, this.dismissedAt});

  bool get isDismissed => dismissedAt != null;
}

/// Decides whether the live bar is on screen.
///
/// Pure on purpose. Every rule here is a product decision about how long a
/// result stays up and what counts as having seen it, and those are exactly the
/// decisions that are miserable to verify by hand-tapping a widget.
LiveOrderVisibility resolveLiveOrderVisibility({
  required OrderTracking? tracking,
  required bool isLoading,
  required bool hasError,
  required LiveOrderConclusion? conclusion,
  required DateTime now,
  Duration deliveredAutoHideDelay = liveOrderDeliveredAutoHideDelay,
}) {
  // A failed read must never surface on the home screen. The customer came here
  // to browse pizza; a tracking outage is not their problem to solve, and there
  // is a retry on the tracking screen if they want to go looking for the order.
  if (isLoading || hasError) return LiveOrderVisibility.hidden;
  if (tracking == null) return LiveOrderVisibility.hidden;

  switch (tracking.stage) {
    case OrderStage.delivered:
      if (conclusion?.isDismissed ?? false) return LiveOrderVisibility.hidden;
      final shownAt = conclusion?.firstShownTerminalAt;
      // Never recorded yet means the bar has not painted it yet, which means it
      // is about to — so show it rather than hiding it for one frame.
      if (shownAt == null) return LiveOrderVisibility.delivered;
      final shownFor = now.difference(shownAt);
      if (shownFor.isNegative) return LiveOrderVisibility.delivered;
      return shownFor >= deliveredAutoHideDelay
          ? LiveOrderVisibility.hidden
          : LiveOrderVisibility.delivered;

    case OrderStage.cancelled:
      // Acknowledgement is required. A cancellation that quietly slid away
      // after a minute is the one status a customer has to be told about.
      return (conclusion?.isDismissed ?? false)
          ? LiveOrderVisibility.hidden
          : LiveOrderVisibility.cancelled;

    case OrderStage.orderConfirmed:
    case OrderStage.preparingInKitchen:
    case OrderStage.readyForPickup:
    case OrderStage.riderHeadingToBranch:
    case OrderStage.outForDelivery:
      return LiveOrderVisibility.active;

    case OrderStage.unknown:
      // Never shown on the bar, even though the tracking screen can open it and
      // admit what it does not know. The bar makes claims unprompted to someone
      // who is trying to buy pizza; "we cannot read this order" is not a reason
      // to occupy their screen. And a bar that surfaced an unreadable order is
      // exactly how a month-old order ended up here pretending to be cooking.
      return LiveOrderVisibility.hidden;
  }
}
