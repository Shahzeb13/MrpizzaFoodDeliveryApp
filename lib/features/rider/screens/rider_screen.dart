import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';
import '../../../widgets/app_drawer.dart';
import '../data/rider_repository.dart';
import '../logic/delivery_actions.dart';
import '../models/rider_availability.dart';
import '../models/rider_delivery.dart';
import '../providers/rider_providers.dart';
import 'rider_earnings_screen.dart';
import 'rider_history_screen.dart';

/// The rider's working screen: availability, the job in hand, anything waiting
/// to be accepted, and a peek at recent deliveries.
///
/// Every value on this screen comes from the database. The previous version of
/// this file was 956 lines of invented data with no database access at all.
class RiderScreen extends ConsumerWidget {
  const RiderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(riderDetailsProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Rider Dashboard'),
        actions: [
          IconButton(
            tooltip: 'My deliveries',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const RiderHistoryScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'My earnings',
            icon: const Icon(Icons.payments_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const RiderEarningsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: detailsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _RiderMessage(
          message: 'Could not load your rider account.',
          detail: '$error',
          onRetry: () => ref.invalidate(riderDetailsProvider),
        ),
        data: (details) {
          if (details == null) {
            return const _RiderMessage(
              message: 'Your rider account is not set up yet.',
              detail:
                  'Ask the branch to add you, then pull down to refresh. '
                  'Nothing you do here will be visible to the shop until then.',
            );
          }
          return _RiderDashboard(details: details);
        },
      ),
    );
  }
}

class _RiderDashboard extends ConsumerWidget {
  const _RiderDashboard({required this.details});

  final RiderDetails details;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveriesAsync = ref.watch(riderDeliveriesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(riderDeliveriesProvider);
        ref.invalidate(riderDetailsProvider);
        ref.invalidate(riderEarningsProvider);
        await ref.read(riderDeliveriesProvider.future);
      },
      child: deliveriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _RiderMessage(
          message: 'Could not load your deliveries.',
          detail: '$error',
          onRetry: () => ref.invalidate(riderDeliveriesProvider),
        ),
        data: (deliveries) {
          final offers = pendingOffersFor(deliveries);
          final active = activeDeliveryFor(deliveries);
          final history = deliveredHistoryFor(deliveries);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const SizedBox(height: 8),
              _AvailabilityToggle(availability: details.availability),
              const SizedBox(height: 20),
              const _TotalsStrip(),
              const SizedBox(height: 20),
              if (active != null) ...[
                const MrSectionTitle(title: 'Current Delivery'),
                const SizedBox(height: 12),
                _ActiveDeliveryCard(delivery: active),
                const SizedBox(height: 24),
              ],
              if (offers.isNotEmpty) ...[
                const MrSectionTitle(title: 'Waiting for you'),
                const SizedBox(height: 12),
                ...offers.map((offer) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _OfferCard(delivery: offer),
                    )),
                const SizedBox(height: 14),
              ],
              if (active == null && offers.isEmpty) ...[
                const SizedBox(height: 12),
                const _RiderMessage(
                  message: 'No deliveries waiting',
                  detail:
                      'When the shop assigns you an order it will appear here.',
                ),
              ],
              if (history.isNotEmpty) ...[
                const MrSectionTitle(title: 'Recent deliveries'),
                const SizedBox(height: 12),
                ...history
                    .take(3)
                    .map((delivery) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _HistoryRow(delivery: delivery),
                        )),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The go online / go offline control. A refusal from the database — most often
/// "Finish your current delivery first" — is shown in the rider's own words.
class _AvailabilityToggle extends ConsumerWidget {
  const _AvailabilityToggle({required this.availability});

  final RiderAvailability availability;

  bool get isAvailable => availability == RiderAvailability.available;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBusy = ref.watch(riderAvailabilityController).isLoading;

    return MrCard(
      child: Row(
        children: [
          MrIconWell(
            icon: isAvailable
                ? Icons.bolt_rounded
                : Icons.power_settings_new_rounded,
            color: isAvailable ? AppColors.success : AppColors.textSecondary,
            background: isAvailable ? AppColors.primaryTint : AppColors.sand,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAvailable ? 'You are online' : 'You are offline',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  availability == RiderAvailability.onDelivery
                      ? 'Finish the delivery in hand first.'
                      : isAvailable
                          ? 'The shop can assign you orders.'
                          : 'You will not be given new orders.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (availability != RiderAvailability.onDelivery)
            FilledButton(
              onPressed: isBusy
                  ? null
                  : () => _toggleAvailability(context, ref),
              child: Text(isAvailable ? 'Go Offline' : 'Go Online'),
            ),
        ],
      ),
    );
  }

  Future<void> _toggleAvailability(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(riderAvailabilityController.notifier);
    try {
      if (isAvailable) {
        await controller.goOffline();
      } else {
        await controller.goOnline();
      }
    } on RiderRepositoryException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

/// Lifetime totals, not today's.
///
/// The name said "today" and nothing anywhere filtered by date, so a rider with
/// 40 deliveries this month read them as today's takings. The rate is shown as
/// "Rate unavailable" rather than `Rs. 0`, because a zero is indistinguishable
/// from not being paid.
class _TotalsStrip extends ConsumerWidget {
  const _TotalsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earningsAsync = ref.watch(riderEarningsProvider);
    final rateAsync = ref.watch(payoutRateProvider);
    final countAsync = ref.watch(riderDeliveriesProvider);

    final rate = rateAsync.valueOrNull;
    final earnings = earningsAsync.valueOrNull;
    final completed = countAsync.valueOrNull == null
        ? null
        : completedCountFor(countAsync.valueOrNull!);

    final earningsLabel = rate != null && rate > 0
        ? 'Rs. ${(earnings ?? 0).toStringAsFixed(0)}'
        : (rate == null ? '—' : 'Rate unavailable');

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Deliveries completed (all time)',
            value: completed == null ? '—' : '$completed',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'Earnings (all time)',
            value: earningsLabel,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return MrCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ActiveDeliveryCard extends ConsumerWidget {
  const _ActiveDeliveryCard({required this.delivery});

  final RiderDelivery delivery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = primaryActionFor(delivery);
    // Both buttons must lock while a transition is in flight. Without this a
    // double-tap fires two RPCs and the second refusal ("this delivery is no
    // longer available") appears immediately after the rider accepted it.
    final busy = ref.watch(riderTransitionController).isLoading;

    return MrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  delivery.customerName.isEmpty
                      ? 'Delivery ${delivery.billNumber}'
                      : delivery.customerName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  delivery.billNumber,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DeliveryBody(delivery: delivery),
          const SizedBox(height: 14),
          _ContactActions(delivery: delivery),
          if (action != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: busy
                    ? null
                    : () => _runAction(context, ref, action.action),
                child: Text(action.label),
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: busy
                  ? null
                  : () => _reportProblem(context, ref),
              child: const Text('Report a problem'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reportProblem(BuildContext context, WidgetRef ref) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What went wrong?',
                style: Theme.of(sheetContext).textTheme.titleSmall),
            const SizedBox(height: 12),
            for (final option in const [
              'Customer is not answering',
              'Customer refused the order',
              'Customer is not at the address',
              'Address could not be found',
            ])
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(option),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(option),
                ),
              ),
          ],
        ),
      ),
    );
    if (reason == null || !context.mounted) return;
    await _runAction(context, ref, RiderAction.fail, reason: reason);
  }

  Future<void> _runAction(
    BuildContext context,
    WidgetRef ref,
    RiderAction action, {
    String? reason,
  }) async {
    final controller = ref.read(riderTransitionController.notifier);
    try {
      switch (action) {
        case RiderAction.markPickedUp:
          await controller.markPickedUp(delivery.assignmentId);
          break;
        case RiderAction.complete:
          await controller.completeDelivery(delivery.assignmentId);
          break;
        case RiderAction.accept:
          await controller.claimOffer(delivery.assignmentId);
          break;
        case RiderAction.decline:
          await controller.declineOffer(delivery.assignmentId);
          break;
        case RiderAction.fail:
          await controller.failDelivery(
              delivery.assignmentId, reason ?? 'Not specified');
          break;
      }
    } on RiderRepositoryException catch (error) {
      // The server state is unknown after a refusal or a dropped connection,
      // so re-read rather than leaving the rider looking at stale work.
      ref.invalidate(riderDeliveriesProvider);
      ref.invalidate(riderDetailsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _OfferCard extends ConsumerWidget {
  const _OfferCard({required this.delivery});

  final RiderDelivery delivery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(riderTransitionController.notifier);
    final busy = ref.watch(riderTransitionController).isLoading;

    return MrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(delivery.billNumber,
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              Text('New order',
                  style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 10),
          _DeliveryBody(delivery: delivery),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _guard(context,
                          () => controller.declineOffer(delivery.assignmentId)),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () => _guard(context,
                          () => controller.claimOffer(delivery.assignmentId)),
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The shared part of a job card: where to go and what is in the bag.
///
/// The branch and the bag contents render even when the contact details are
/// missing. A rider told to "call the branch" still has to know which shop to
/// turn up at and what to expect.
class _DeliveryBody extends StatelessWidget {
  const _DeliveryBody({required this.delivery});

  final RiderDelivery delivery;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!delivery.hasContactDetails)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Contact details unavailable — this order was placed before the '
              'app recorded them. Call the branch.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.warning),
            ),
          ),
        if (delivery.deliveryAddress.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_rounded,
                  size: 16, color: AppColors.textLight),
              const SizedBox(width: 6),
              Expanded(
                child: Text(delivery.deliveryAddress,
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        if (delivery.itemSummary.isNotEmpty)
          Text(delivery.itemSummary,
              style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text('Collect from ${delivery.branchName}',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Call and maps buttons, shown only when there is something to call or point
/// at. This is what keeps a pre-snapshot order from rendering empty buttons.
class _ContactActions extends StatelessWidget {
  const _ContactActions({required this.delivery});

  final RiderDelivery delivery;

  @override
  Widget build(BuildContext context) {
    final canCall = delivery.customerPhone.trim().isNotEmpty;
    final mapsUrl = delivery.mapsUrl;

    if (!canCall && mapsUrl == null) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        if (canCall)
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.phone_rounded, size: 18),
              label: const Text('Call'),
              onPressed: () => _open(
                context,
                Uri(scheme: 'tel', path: delivery.customerPhone.trim()),
                'This phone cannot make calls.',
              ),
            ),
          ),
        if (canCall && mapsUrl != null) const SizedBox(width: 10),
        if (mapsUrl != null)
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.map_rounded, size: 18),
              label: const Text('Open in Maps'),
              onPressed: () => _open(
                context,
                Uri.parse(mapsUrl),
                'No maps app is installed on this phone.',
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _open(BuildContext context, Uri uri, String failureMessage) async {
    final opened = await launchUrl(uri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.delivery});

  final RiderDelivery delivery;

  @override
  Widget build(BuildContext context) {
    return MrCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(delivery.billNumber,
                    style: Theme.of(context).textTheme.titleSmall),
                if (delivery.customerName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(delivery.customerName,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          Text(
            delivery.assignmentStatus,
            style: TextStyle(
              color: delivery.assignmentStatus == 'delivered'
                  ? AppColors.success
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// The full-width message used for "not set up", "no work" and load failures.
class _RiderMessage extends StatelessWidget {
  const _RiderMessage({
    required this.message,
    required this.detail,
    this.onRetry,
  });

  final String message;
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
            const MrIconWell(
              icon: Icons.two_wheeler_rounded,
              size: 28,
              background: AppColors.sand,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shared by the offer and active cards: surfaces a database refusal.
Future<void> _guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on RiderRepositoryException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}
