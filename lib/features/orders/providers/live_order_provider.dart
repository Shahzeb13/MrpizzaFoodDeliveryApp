import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/order_tracking.dart';
import '../presentation/live_order_visibility.dart';
import 'order_tracking_provider.dart';

/// How old an order may be and still be adopted onto the bar when the app opens.
///
/// This is a data-hygiene guard, not a delivery-time promise. Mr Pizza delivers
/// well inside an hour, so an order that is still un-delivered an hour after it
/// was placed is not "slow" — its status is stale or the branch never moved it,
/// which is exactly the state this app's earlier orders were left in during
/// development. Adopting one of those put a week-old pizza back on the home
/// screen claiming to be in the oven.
///
/// It deliberately does NOT apply to an order this session already adopted.
/// Once the bar has picked up an order it follows that one to the end, however
/// long it takes: the shop owns delivery timing, and dropping a real order off
/// the customer's screen because it ran late is a worse failure than showing
/// them stale data.
const Duration liveOrderMaxAdoptionAge = Duration(hours: 1);

/// The single order the bar is committed to showing, once chosen.
///
/// This is what replaced a repeated "give me the newest unfinished order"
/// lookup. A lookup has no end: the moment the order it was following reached a
/// terminal state, the next run simply kept walking backwards through the
/// customer's history until it found something that looked unfinished, and the
/// bar popped back up showing a previous order with no event to explain it.
///
/// A pin cannot do that. Once set it either still points at an order the bar is
/// following, or it has been cleared and there is genuinely nothing to show.
final pinnedLiveOrderIdProvider = StateProvider<String?>((ref) => null);

/// True once this session's followed order has concluded, which closes adoption
/// for good.
///
/// This is the flag that stops the bar wandering backwards through the
/// customer's history. Adoption used to be free to run again whenever the
/// lookup was invalidated, which meant that once an order finished, the next run
/// would happily pick up an *older* order that was somehow still unfinished — so
/// a customer who ordered twice and whose newer order completed first would be
/// shown the older one, with nothing having prompted it.
///
/// One order per session, unless the customer places a new one. Ordering again
/// is an explicit decision and re-opens adoption; nothing else does.
///
/// Written only from [stopFollowingLiveOrder] and [startFollowingNewlyPlacedOrder],
/// never from inside a resolving provider. Setting it during resolution tripped
/// Riverpod's guard on the provider's own dependencies: writing the pin marks
/// this provider outdated, so any second write through the same `ref` throws.
final liveOrderAdoptionClosedProvider = StateProvider<bool>((ref) => false);

/// Picks the one order the bar may adopt, or null if there is nothing worth
/// adopting.
///
/// Pure, so the adoption rules — status, retirement and age — can be tested
/// without a widget tree or a database. [orders] is treated as newest-first by
/// sorting here rather than trusting the caller's ordering, because "newest
/// qualifying order" is now a rule with consequences and not just a convenience.
String? selectLiveOrderToFollow({
  required List<OrderSummary> orders,
  required Map<String, LiveOrderConclusion> conclusions,
  required DateTime now,
  Duration maxAge = liveOrderMaxAdoptionAge,
}) {
  final newestFirst = [...orders]
    ..sort((a, b) {
      // An order with no timestamp cannot be age-checked, and skipping it is the
      // safe direction: better to show no bar than to adopt something unverifiable.
      final aAt = a.createdAt;
      final bAt = b.createdAt;
      if (aAt == null) return 1;
      if (bAt == null) return -1;
      return bAt.compareTo(aAt);
    });

  for (final order in newestFirst) {
    // Delivered, cancelled, and unreadable statuses are all already excluded by
    // isStillMoving — an unknown status is explicitly NOT still-moving.
    if (!order.isStillMoving) continue;

    // Retired means the customer was shown how this order ended and said they
    // were done with it. Being retired outranks every other signal here.
    if (conclusions[order.orderId]?.isDismissed ?? false) continue;

    final createdAt = order.createdAt;
    if (createdAt == null) continue;
    if (now.difference(createdAt) > maxAge) continue;

    return order.orderId;
  }
  return null;
}

/// The order the persistent home/menu bar should be showing.
///
/// Deliberately independent of `trackedOrderIdProvider`. That provider records
/// whichever order the customer last opened, and opening a delivered order from
/// three days ago writes a terminal id into it — which would pin the live bar
/// to a finished order forever.
///
/// Resolution happens exactly once per order: if a pin already exists that id
/// is returned untouched, and no amount of re-running this provider will move
/// the bar onto a different order.
final liveOrderIdProvider = FutureProvider<String?>((ref) async {
  final pinned = ref.watch(pinnedLiveOrderIdProvider);
  if (pinned != null && pinned.isNotEmpty) return pinned;

  // Already followed something this session and it has concluded. The pin was
  // released at that point, and running the lookup again would adopt whatever
  // unfinished order happened to be next in the history rather than nothing.
  // "No order to show" is the honest answer; an older order is not.
  //
  // Read rather than watched, because the only two places that change it both
  // invalidate this provider directly anyway.
  if (ref.read(liveOrderAdoptionClosedProvider)) return null;

  final orders = await ref.watch(myOrdersProvider.future);
  final adopted = selectLiveOrderToFollow(
    orders: orders,
    conclusions: ref.read(liveOrderConclusionsProvider),
    now: DateTime.now(),
  );
  if (adopted == null) return null;

  // Deferred out of the provider body: this runs while the bar's first frame
  // may still be building, and Riverpod rejects writes to another provider
  // during build.
  Future.microtask(() {
    ref.read(pinnedLiveOrderIdProvider.notifier).state = adopted;
  });
  return adopted;
});

/// Live state of the order the home/menu bar follows.
///
/// Not `autoDispose`, unlike the tracking screen's provider, because the whole
/// point of this one is to keep watching while the customer browses. If it
/// dropped whenever the widget went away, the socket would tear down on every
/// route change and the bar would show a fresh spinner each time it came back.
///
/// It also opens its realtime channel under its own prefix. Both this and the
/// tracking screen follow the same in-flight order, and realtime_client keys
/// subscriptions by channel name — sharing one name would have them fighting
/// over a single socket join, and one of them would go quiet without an error.
final liveOrderTrackingProvider = StreamProvider<OrderTracking?>((ref) async* {
  final orderId = await ref.watch(liveOrderIdProvider.future);
  if (orderId == null || orderId.isEmpty) return;

  yield* ref
      .watch(orderTrackingRepositoryProvider)
      .watchOrderTracking(orderId, channelPrefix: 'live-order');
});

/// Re-runs [liveOrderIdProvider] so the bar notices orders that appeared since
/// it last looked.
///
/// Without this the bar is correct forever and permanently wrong. Both providers
/// below are caching ones, so the very first lookup of the session decides what
/// the bar shows for as long as the app stays open: install the app with no
/// order in flight, place one, and the bar stays hidden on the truthful but
/// stale answer "you have nothing active" from before the order existed.
///
/// `myOrdersProvider` has to be dropped as well as [liveOrderIdProvider],
/// because it is the one holding the cached list — invalidating only the outer
/// provider would re-run the same lookup against the same stale rows.
///
/// This deliberately leaves any existing pin alone. Re-checking whether an
/// in-flight order has changed is the point; being re-offered a different order
/// is the bug.
void refreshLiveOrderLookup(WidgetRef ref) {
  ref.invalidate(myOrdersProvider);
  ref.invalidate(liveOrderIdProvider);
}

/// Points the bar at the order the customer just placed, whatever it was
/// following before.
///
/// Called after a successful checkout. The previous pin is dropped outright
/// rather than retired-then-replaced, because the newest order always wins: a
/// customer who orders again has told us which order they care about. An order
/// abandoned this way is not deleted or hidden anywhere — it stays in My Orders
/// and on its own tracking screen.
void startFollowingNewlyPlacedOrder(WidgetRef ref) {
  ref.read(pinnedLiveOrderIdProvider.notifier).state = null;
  // Ordering again re-opens adoption. The customer has just told us which order
  // they care about, so the bar is allowed to find it even though it had already
  // committed to an earlier one this session.
  ref.read(liveOrderAdoptionClosedProvider.notifier).state = false;
  refreshLiveOrderLookup(ref);
}

/// Stops following [orderId], closes adoption, and lets a later explicit order
/// re-open it.
///
/// Called once the bar has finished showing a terminal state — the customer
/// dismissed it, or the delivered confirmation window elapsed. Only acts when
/// the pin still refers to [orderId], so a late timer firing after the customer
/// has already started following a new order cannot release that one.
///
/// Closing adoption is what stops the bar from falling back to an older
/// unfinished order the moment the pin comes free. Without it, releasing the pin
/// was not enough: the next resolution would select whatever came next in the
/// history.
void stopFollowingLiveOrder(WidgetRef ref, String orderId) {
  if (orderId.isEmpty) return;
  if (ref.read(pinnedLiveOrderIdProvider) != orderId) return;
  ref.read(pinnedLiveOrderIdProvider.notifier).state = null;
  ref.read(liveOrderAdoptionClosedProvider.notifier).state = true;
}

/// What the customer has already been shown about each finished order.
///
/// Keyed by order id so dismissing Tuesday's cancellation cannot hide a new one
/// on Thursday. Written from the bar itself, which is the only surface that
/// knows when it actually painted a terminal state.
final liveOrderConclusionsProvider =
    StateProvider<Map<String, LiveOrderConclusion>>((ref) => <String, LiveOrderConclusion>{});

/// Records that [orderId] just reached a terminal state, keeping any dismissal
/// already recorded for it.
///
/// Called from the bar's build, after the frame, so the write never happens
/// while the widget tree is being built.
void recordLiveOrderFirstShownTerminal(WidgetRef ref, String orderId) {
  _writeConclusion(
    ref,
    orderId,
    (existing) => LiveOrderConclusion(
      firstShownTerminalAt:
          existing?.firstShownTerminalAt ?? DateTime.now(),
      dismissedAt: existing?.dismissedAt,
    ),
  );
}

/// Records that the customer acknowledged [orderId] and does not want to be
/// shown it again.
///
/// Also releases the pin, so a finished order cannot keep the bar pointed at it
/// and block the next order from being adopted.
void dismissLiveOrderConclusion(WidgetRef ref, String orderId) {
  final now = DateTime.now();
  _writeConclusion(
    ref,
    orderId,
    (existing) => LiveOrderConclusion(
      firstShownTerminalAt: existing?.firstShownTerminalAt ?? now,
      dismissedAt: now,
    ),
  );
  stopFollowingLiveOrder(ref, orderId);
}

void _writeConclusion(
  WidgetRef ref,
  String orderId,
  LiveOrderConclusion Function(LiveOrderConclusion? existing) build,
) {
  // Guarded here rather than at each call site: an empty id would otherwise
  // become a map key that some other nameless order could collide with.
  if (orderId.isEmpty) return;

  ref.read(liveOrderConclusionsProvider.notifier).update((existing) {
    return <String, LiveOrderConclusion>{
      ...existing,
      orderId: build(existing[orderId]),
    };
  });
}
