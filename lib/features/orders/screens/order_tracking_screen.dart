import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/widgets.dart';
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
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Live Order Tracking'),
          backgroundColor: AppColors.surface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () {
              if (canGoBack) {
                Navigator.of(context).pop();
              } else {
                context.go('/home');
              }
            },
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

  void _announceStageChange(OrderStage stage, String status) {
    setState(() {
      _announcedStage = stage;
      _updateBanner = stageHeadline(stage, widget.tracking);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tracking = widget.tracking;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(activeOrderTrackingProvider);
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

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSoft,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPickup ? Icons.storefront_rounded : Icons.home_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                isPickup ? 'Collecting from the branch' : 'Delivering to',
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isPickup
                ? (tracking.branchName ?? 'The branch handling your order')
                : (tracking.deliveryAddress ??
                    'No address was saved on this order'),
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (!isPickup && tracking.branchName != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.storefront_rounded,
                    color: AppColors.textLight, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Being prepared at ${tracking.branchName}',
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 12,
                      color: AppColors.textLight,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemsSection(BuildContext context, OrderTracking tracking) {
    if (tracking.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MrSectionTitle(
          eyebrow: 'What You Ordered',
          title: 'Order Items',
          trailing: Text(
            'Rs. ${tracking.total.toInt()}',
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...tracking.items.map(_buildItemRow),
        const SizedBox(height: 8),
        _buildTotalsPanel(),
      ],
    );
  }

  Widget _buildItemRow(TrackedOrderItem item) {    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowSoft,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildItemThumbnail(imageUrl: item.imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.name,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'x${item.quantity}',
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Rs. ${item.lineTotal.toInt()}',
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemThumbnail({required String? imageUrl}) {
    final url = (imageUrl ?? '').trim();

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: url.isEmpty
          ? Container(
              width: 48,
              height: 48,
              color: AppColors.sand,
              child: const Center(
                child: Text('🍕', style: TextStyle(fontSize: 22)),
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
                color: AppColors.sand,
                child: const Center(
                    child: Text('🍕', style: TextStyle(fontSize: 22))),
              ),
            ),
    );
  }

  /// The money lines, all read from the `orders` row.
  ///
  /// The total is the database's, not a subtraction done in the widget — the
  /// same figure the kitchen, the ledger and the receipt are working from.
  Widget _buildTotalsPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _totalLine('Subtotal', 'Rs. ${tracking.subtotal.toInt()}'),
          if (tracking.tax > 0) ...[
            const SizedBox(height: 4),
            _totalLine('Tax', 'Rs. ${tracking.tax.toInt()}'),
          ],
          if (tracking.deliveryCharges > 0) ...[
            const SizedBox(height: 4),
            _totalLine('Delivery', 'Rs. ${tracking.deliveryCharges.toInt()}'),
          ],
          if (tracking.discountAmount > 0) ...[
            const SizedBox(height: 4),
            _totalLine(
              'Voucher Discount',
              '-Rs. ${tracking.discountAmount.toInt()}',
              isDiscount: true,
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: AppColors.border, height: 1),
          ),
          _totalLine('Total', 'Rs. ${tracking.total.toInt()}', bold: true),
        ],
      ),
    );
  }

  Widget _totalLine(String label, String value,
      {bool bold = false, bool isDiscount = false}) {
    final color = isDiscount
        ? AppColors.success
        : bold
            ? AppColors.primary
            : AppColors.textSecondary;

    final style = TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: bold ? 14 : 13,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: color,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Both sides are flexed: a long voucher label or a four-figure total
        // must wrap instead of striping the edge of the customer's phone.
        Expanded(
          child: Text(label, style: style, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 10),
        Text(value, style: style),
      ],
    );
  }

  /// The five real steps, lit by the stage the order is actually in.
  ///
  /// The old version's second step was permanently titled "Baking in Wood-Fired
  /// Oven" and was marked done purely by which fake enum value was in memory.
  /// Both now come from `orders.status`, including the "ready for pickup" stage
  /// the branch added so a customer can see their food bagged and waiting for a
  /// rider rather than still being cooked.
  Widget _buildPipelineSection(BuildContext context, OrderTracking tracking) {
    final stage = tracking.stage;
    final reached = pipelineProgressFor(stage);
    final riderName = tracking.rider?.fullName;
    final onTheWaySubtitle = riderName == null
        ? 'A rider is bringing your order'
        : '$riderName is bringing your order';

    final steps = <_PipelineStep>[
      const _PipelineStep(
        title: 'Order Confirmed',
        subtitle: 'The branch has your order',
        icon: Icons.check_circle,
      ),
      const _PipelineStep(
        title: 'Preparing Your Food',
        subtitle: 'The kitchen is cooking your order',
        icon: Icons.local_fire_department,
      ),
      const _PipelineStep(
        title: 'Ready for Pickup',
        subtitle: 'Your food is packed and waiting for the rider',
        icon: Icons.takeout_dining_rounded,
      ),
      _PipelineStep(
        title: 'On The Way',
        subtitle: onTheWaySubtitle,
        icon: Icons.delivery_dining,
      ),
      const _PipelineStep(
        title: 'Delivered',
        subtitle: 'Enjoy your Mr. Pizza order',
        icon: Icons.home,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MrSectionTitle(eyebrow: 'Progress', title: 'Order Pipeline'),
        const SizedBox(height: 18),
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

  Widget _buildTrackingStep({
    required BuildContext context,
    required int index,
    required _PipelineStep step,
    required bool isCompleted,
    required bool isCurrent,
    required bool isLast,
  }) {
    final color = isCurrent
        ? AppColors.primary
        : isCompleted
            ? AppColors.success
            : AppColors.textLight;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            PulsingStepRing(
              active: isCurrent,
              color: AppColors.primary,
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: isCurrent ? 2 : 1.4),
                ),
                child: Icon(step.icon, color: color, size: 20),
              ),
            ),
            AnimatedStepConnector(
              filled: isCompleted,
              isLast: isLast,
            ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 320),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color:
                        isCurrent ? AppColors.primary : AppColors.textPrimary,
                    fontFamily: AppTheme.fontFamily,
                  ),
                  child: Text(step.title),
                ),
                const SizedBox(height: 2),
                Text(step.subtitle, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
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