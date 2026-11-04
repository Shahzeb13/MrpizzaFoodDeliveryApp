import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/neumorphic.dart';
import '../../../core/theme/widgets.dart';
import '../../loyalty/providers/loyalty_provider.dart';
import '../../loyalty/widgets/spend_points_control.dart';
import '../models/order_tracking.dart';
import '../presentation/order_status_copy.dart';
import '../providers/order_tracking_provider.dart';
import 'order_tracking_animations.dart';

export '../presentation/order_status_copy.dart'
    show
        formatClockTime,
        formatDayLabel,
        pipelineProgressFor,
        riderAssignmentLabel,
        stageColorFor,
        stageHeadline,
        stageSubtitle,
        statusLabel;


/// Live progress of a real order, read from the database.
///
/// The screen this replaces rendered a `DemoOrder`: a `Timer` assigned a rider
/// called "Test Rider" 2.5 seconds after checkout, the headline was hardcoded to
/// "Baking in Wood-Fired Oven" whatever the order was actually doing, a rider
/// called "Marco" was drawn 1.2 km away on a map of invented roads, and the
/// order number was the literal string `ORDER #MP-9842`. Every value below now
/// comes from `order_tracking()` — the order row, its items, the assignment the
/// branch actually made and the status changes the branch and rider recorded.
class OrderTrackingScreen extends ConsumerWidget {
  const OrderTrackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackingAsync = ref.watch(activeOrderTrackingProvider);

    // Checkout reaches this screen with `go`, which REPLACES the route stack
    // rather than stacking on it — so there is nothing to pop, and a plain
    // `Navigator.pop` closed the whole app instead of going back. Both the
    // button and the Android system back button route home when there is
    // nothing underneath to return to.
    final canGoBack = Navigator.of(context).canPop();

    return PopScope(
      canPop: canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.go('/home');
      },
      child: Scaffold(
        backgroundColor: NeuColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          title: const Text(
            'Live Order Tracking',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: NeuColors.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
          leading: Center(
            child: NeuCircleButton(
              size: 40,
              onPressed: () {
                if (canGoBack) {
                  Navigator.of(context).pop();
                } else {
                  context.go('/home');
                }
              },
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: NeuColors.textPrimary,
              ),
            ),
          ),
        ),
        body: trackingAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _TrackingProblem(
            title: 'We could not load your order.',
            detail: '$error',
            onRetry: () => ref.invalidate(activeOrderTrackingProvider),
          ),
          data: (tracking) {
            if (tracking == null) {
              return const _TrackingProblem(
                title: 'No orders to track yet',
                detail:
                    'Once you place an order it will be tracked here with its real '
                    'status, bill number and rider. Nothing on this screen is made '
                    'up, so there is nothing to show until there is a real order.',
              );
            }
            return _OrderTrackingBody(tracking: tracking);
          },
        ),
      ),
    );
  }
}

class _OrderTrackingBody extends ConsumerStatefulWidget {
  const _OrderTrackingBody({required this.tracking});

  final OrderTracking tracking;

  @override
  ConsumerState<_OrderTrackingBody> createState() => _OrderTrackingBodyState();
}

class _OrderTrackingBodyState extends ConsumerState<_OrderTrackingBody> {
  /// The last change the branch made, shown briefly in a banner. Null until
  /// something actually changes — a customer should not be told their order
  /// "just" moved when they have only just opened the screen.
  String? _updateBanner;

  /// Which stage produced [_updateBanner], so it can be coloured to match. A
  /// cancellation is announced in the danger colour, not the success green.
  OrderStage? _announcedStage;

  /// The order this screen is showing. Named so the builders below read as
  /// plain functions of the order rather than reaching into `widget` at every
  /// line.
  OrderTracking get tracking => widget.tracking;

  @override
  void didUpdateWidget(covariant _OrderTrackingBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    final previous = oldWidget.tracking.status;
    final current = widget.tracking.status;
    if (previous == current) return;

    // Reaching `delivered` credits points through a database trigger, and
    // reaching `cancelled` refunds whatever was spent on this order. Both write
    // a ledger row the app is not subscribed to, so the balance held in memory is
    // now stale and has to be re-read — otherwise the customer watches their
    // points stay put through the exact moment they changed.
    if (_creditsPoints(current) || _creditsPoints(previous)) {
      refreshLoyaltyBalance(ref);
    }
  }

  /// True for the statuses at which the database moves points by itself.
  static bool _creditsPoints(String status) =>
      status == 'delivered' || status == 'cancelled';

  void _announceStageChange(OrderStage stage, String status) {
    setState(() {
      _announcedStage = stage;
      _updateBanner = stageHeadline(stage, widget.tracking);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tracking = widget.tracking;

    // Watched rather than only invalidated: watching is what makes the
    // `refreshLoyaltyBalance` calls in `didUpdateWidget` actually re-read, and
    // it is where the points credited for this order come from.
    final loyalty = ref.watch(loyaltyBalanceProvider).valueOrNull;
    final pointsEarned = loyalty?.pointsEarnedOnOrder(tracking.orderId) ?? 0;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(activeOrderTrackingProvider);
        refreshLoyaltyBalance(ref);
        await ref.read(activeOrderTrackingProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Fires the animation and the banner when the dashboard moves the
          // order. Sits above the list, out of the way.
          OrderStageChangeNotifier(
            tracking: tracking,
            onStageChanged: _announceStageChange,
          ),
          if (_updateBanner != null) ...[
            OrderUpdateBanner(
              stage: _announcedStage!,
              message: _updateBanner!,
            ),
          ],
          AnimatedOrderStatusHeader(
            tracking: tracking,
            pulseKey: trackingPulseKey(tracking),
          ),
          const SizedBox(height: 20),
          _buildRiderSection(context, tracking),
          _buildDeliveryPanel(context, tracking),
          const SizedBox(height: 24),
          _buildItemsSection(context, tracking),
          if (pointsEarned > 0) ...[
            const SizedBox(height: 16),
            _buildPointsCreditedCard(context, pointsEarned),
          ],
          const SizedBox(height: 24),
          _buildPipelineSection(context, tracking),
          if (tracking.timeline.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildHistorySection(context),
          ],
        ],
      ),
    );
  }

  /// The rider the branch actually assigned, with a call button only when there
  /// is a real number to dial.
  ///
  /// The card grows into place when the assignment lands. That is the moment a
  /// customer is actually waiting for, so it gets motion rather than appearing
  /// silently between one frame and the next.
  Widget _buildRiderSection(BuildContext context, OrderTracking tracking) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: tracking.rider == null
          ? const SizedBox(width: double.infinity)
          : Column(
              children: [
                _buildRiderCard(context, tracking),
                const SizedBox(height: 20),
              ],
            ),
    );
  }

  Widget _buildRiderCard(BuildContext context, OrderTracking tracking) {
    final rider = tracking.rider!;
    final name = rider.fullName ?? 'Your rider';
    final assignment = riderAssignmentLabel(rider.assignmentStatus);

    return MrCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(20),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.borderDeep),
            ),
            child: const Icon(Icons.delivery_dining,
                color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  assignment,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (rider.canBeCalled)
            IconButton(
              tooltip: 'Call your rider',
              icon: const MrIconWell(
                icon: Icons.call_rounded,
                color: AppColors.success,
                background: Color(0xFFE4F1E8),
              ),
              onPressed: () => _callRider(context, name, rider.phone!),
            ),
        ],
      ),
    );
  }

  /// Where the order is going, from the address frozen onto the order row.
  ///
  /// This replaces the old "live map": a hand-drawn grid of fake roads with a
  /// rider pin on it and the line "Rider Marco is 1.2 km away from your
  /// location". No rider coordinates are stored anywhere in the database, so a
  /// moving marker could only ever have been a decoration. What is real — the
  /// address the rider is actually going to, and the branch cooking the food —
  /// is shown instead.
  Widget _buildDeliveryPanel(BuildContext context, OrderTracking tracking) {
    final isPickup = tracking.isPickup;

    return NeuCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: NeuColors.primary,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x59E51926),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  isPickup ? Icons.storefront_rounded : Icons.home_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (isPickup ? 'COLLECTING FROM' : 'DELIVERING TO').toUpperCase(),
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: NeuColors.primary,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPickup
                          ? (tracking.branchName ?? 'The branch handling your order')
                          : (tracking.deliveryAddress ??
                              'No address was saved on this order'),
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: NeuColors.textPrimary,
                        letterSpacing: -0.2,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          NeuInset(
            borderRadius: BorderRadius.circular(14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.access_time_rounded,
                  size: 16,
                  color: NeuColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tracking.branchName != null
                        ? 'Being prepared at ${tracking.branchName}'
                        : 'Being prepared in Abbottabad',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: NeuColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSection(BuildContext context, OrderTracking tracking) {
    if (tracking.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'What you ordered',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: NeuColors.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              'Rs. ${tracking.total.toInt()}',
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: NeuColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...tracking.items.map(_buildItemRow),
        const SizedBox(height: 14),
        _buildTotalsPanel(),
      ],
    );
  }

  /// The points this order actually credited, read from the ledger row the
  /// delivery trigger wrote.
  Widget _buildPointsCreditedCard(BuildContext context, int pointsEarned) {
    return NeuCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: NeuColors.accent,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40FF9800),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.stars_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You earned ${formatPoints(pointsEarned)} points',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: NeuColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Already added to your balance — spend them on your next order.',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 12,
                    color: NeuColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(TrackedOrderItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NeuCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        borderRadius: BorderRadius.circular(24),
        child: Row(
          children: [
            _buildItemThumbnail(imageUrl: item.imageUrl),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: NeuColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Quantity ${item.quantity}',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: NeuColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'Rs. ${item.lineTotal.toInt()}',
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: NeuColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemThumbnail({required String? imageUrl}) {
    final url = (imageUrl ?? '').trim();

    return NeuInset(
      borderRadius: BorderRadius.circular(30),
      padding: const EdgeInsets.all(4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: url.isEmpty
            ? Container(
                width: 48,
                height: 48,
                color: NeuColors.sand,
                child: const Center(
                  child: Text('🍕', style: TextStyle(fontSize: 24)),
                ),
              )
            : Image.network(
                url,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 48,
                  height: 48,
                  color: NeuColors.sand,
                  child: const Center(
                    child: Text('🍕', style: TextStyle(fontSize: 24)),
                  ),
                ),
              ),
      ),
    );
  }

  /// The money lines, all read from the `orders` row in a soft neumorphic card.
  Widget _buildTotalsPanel() {
    return NeuCard(
      borderRadius: BorderRadius.circular(24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        children: [
          _totalLine('Subtotal', 'Rs. ${tracking.subtotal.toInt()}'),
          if (tracking.tax > 0) ...[
            const SizedBox(height: 8),
            _totalLine('Tax', 'Rs. ${tracking.tax.toInt()}'),
          ],
          if (tracking.deliveryCharges > 0) ...[
            const SizedBox(height: 8),
            _totalLine('Delivery', 'Rs. ${tracking.deliveryCharges.toInt()}'),
          ],
          if (tracking.discountAmount > 0) ...[
            const SizedBox(height: 8),
            _totalLine(
              'Discount Applied',
              '-Rs. ${tracking.discountAmount.toInt()}',
              isDiscount: true,
            ),
          ],
          const SizedBox(height: 12),
          _totalLine('Total', 'Rs. ${tracking.total.toInt()}', bold: true),
        ],
      ),
    );
  }

  Widget _totalLine(String label, String value,
      {bool bold = false, bool isDiscount = false}) {
    final color = isDiscount
        ? const Color(0xFF2E7D32)
        : NeuColors.textPrimary;

    final style = TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: bold ? 16 : 14,
      fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
      color: color,
      letterSpacing: bold ? -0.3 : 0,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: style, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 10),
        Text(value, style: style),
      ],
    );
  }

  /// The real steps, lit by the stage the order is actually in.
  ///
  /// The old version's second step was permanently titled "Baking in Wood-Fired
  /// Oven" and was marked done purely by which fake enum value was in memory.
  /// Both now come from `orders.status`, including the "ready for pickup" stage
  /// the branch added so a customer can see their food bagged and waiting for a
  /// rider rather than still being cooked.
  ///
  /// A pickup order gets a different track entirely. It never has a rider and
  /// never travels, so its two delivery steps would be three lines of fiction on
  /// a screen the customer is reading while standing at a counter.
  Widget _buildPipelineSection(BuildContext context, OrderTracking tracking) {
    final stage = tracking.stage;
    final steps = tracking.isPickup
        ? _pickupPipelineSteps(tracking)
        : _deliveryPipelineSteps(tracking);
    final reached = pipelineProgressFor(
      stage,
      stepCount: tracking.pipelineLength,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NeuPillBadge(
          label: 'PROGRESS',
          textColor: NeuColors.primary,
        ),
        const SizedBox(height: 10),
        const Text(
          'Order pipeline',
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: NeuColors.textPrimary,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 20),
        ...steps.asMap().entries.map((entry) {
          final index = entry.key;
          return _buildTrackingStep(
            context: context,
            index: index,
            step: entry.value,
            isCompleted: index < reached,
            isCurrent: index == reached,
            isLast: index == steps.length - 1,
          );
        }),
      ],
    );
  }

  /// The delivery track: confirmed, cooking, bagged, on the way, delivered.
  List<_PipelineStep> _deliveryPipelineSteps(OrderTracking tracking) {
    final riderName = tracking.rider?.fullName;
    return [
      const _PipelineStep(
        title: 'Order confirmed',
        subtitle: 'The branch has your order',
        icon: Icons.check_rounded,
      ),
      const _PipelineStep(
        title: 'Preparing your food',
        subtitle: 'The kitchen is cooking your order',
        icon: Icons.local_fire_department_rounded,
      ),
      const _PipelineStep(
        title: 'Ready for pickup',
        subtitle: 'Your food is packed and waiting for the rider',
        icon: Icons.shopping_bag_outlined,
      ),
      _PipelineStep(
        title: 'On the way',
        subtitle: riderName == null
            ? 'A rider is bringing your order'
            : '$riderName is bringing your order',
        icon: Icons.two_wheeler_rounded,
      ),
      const _PipelineStep(
        title: 'Delivered',
        subtitle: 'Enjoy your Mr. Pizza order',
        icon: Icons.home_outlined,
      ),
    ];
  }

  List<_PipelineStep> _pickupPipelineSteps(OrderTracking tracking) {
    final branch = tracking.branchName;
    return [
      const _PipelineStep(
        title: 'Order confirmed',
        subtitle: 'The branch has your order',
        icon: Icons.check_rounded,
      ),
      const _PipelineStep(
        title: 'Preparing your food',
        subtitle: 'The kitchen is cooking your order',
        icon: Icons.local_fire_department_rounded,
      ),
      _PipelineStep(
        title: 'Ready to collect',
        subtitle: branch == null
            ? 'Your food is packed and waiting at the counter'
            : 'Your food is packed and waiting at $branch',
        icon: Icons.shopping_bag_outlined,
      ),
      const _PipelineStep(
        title: 'Collected',
        subtitle: 'Enjoy your Mr. Pizza order',
        icon: Icons.check_circle_rounded,
      ),
    ];
  }

  Widget _buildTrackingStep({
    required BuildContext context,
    required int index,
    required _PipelineStep step,
    required bool isCompleted,
    required bool isCurrent,
    required bool isLast,
  }) {
    // Styling per screenshot Image 1:
    // Past completed steps: solid red circle with white icon & red glow
    // Current step: dark circular container with subtle outline & white icon (or red if highlighted)
    // Future steps: light neumorphic circular button with muted icon
    final isDone = isCompleted;
    final isActive = isCurrent;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone
                    ? NeuColors.primary
                    : isActive
                        ? const Color(0xFF1F1F24)
                        : NeuColors.background,
                boxShadow: isDone
                    ? const [
                        BoxShadow(
                          color: Color(0x66E51926),
                          blurRadius: 14,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : isActive
                        ? const [
                            BoxShadow(
                              color: Color(0x33E51926),
                              blurRadius: 10,
                              offset: Offset(0, 3),
                            ),
                            BoxShadow(
                              color: Color(0x40000000),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ]
                        : const [
                            BoxShadow(
                              color: Color(0x18000000),
                              blurRadius: 6,
                              offset: Offset(2, 2),
                            ),
                            BoxShadow(
                              color: Colors.white,
                              blurRadius: 6,
                              offset: Offset(-2, -2),
                            ),
                          ],
                border: isActive
                    ? Border.all(color: const Color(0x80E51926), width: 2)
                    : null,
              ),
              child: Center(
                child: Icon(
                  step.icon,
                  size: 22,
                  color: (isDone || isActive)
                      ? Colors.white
                      : NeuColors.textSecondary,
                ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2.5,
                height: 38,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: isDone ? NeuColors.primary.withValues(alpha: 0.3) : const Color(0xFFD6DEE8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: NeuColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  step.subtitle,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: NeuColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The status changes the branch and the rider actually recorded, with the
  /// times they recorded them.
  Widget _buildHistorySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MrSectionTitle(eyebrow: 'Record', title: 'Status History'),
        const SizedBox(height: 14),
        ...tracking.timeline.reversed.map(
          (change) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 16, color: AppColors.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    statusLabel(change.status),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  change.changedAt == null
                      ? ''
                      : '${formatClockTime(change.changedAt!)}  ${formatDayLabel(change.changedAt!)}',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 11,
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _callRider(BuildContext context, String name, String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri(scheme: 'tel', path: phone);

    final launched = await launchUrl(uri);
    if (launched) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text('Could not start a call to $name.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _PipelineStep {
  final String title;
  final String subtitle;
  final IconData icon;

  const _PipelineStep({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

/// A read that failed, or a screen with no real order behind it. Both say so
/// plainly instead of rendering a placeholder order.
class _TrackingProblem extends StatelessWidget {
  const _TrackingProblem({
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final String title;
  final String detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_rounded,
                size: 44, color: AppColors.textLight),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 10),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}