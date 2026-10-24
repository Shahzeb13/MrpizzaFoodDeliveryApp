import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/routing/route_guard.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';
import '../../../widgets/app_drawer.dart';
import '../data/rider_repository.dart';
import '../logic/delivery_actions.dart';

import '../models/rider_delivery.dart';
import '../providers/rider_providers.dart';
import '../widgets/rider_delivery_history_card.dart';

/// The rider's working screen: the job in hand, anything waiting to be accepted,
/// and a peek at recent deliveries.
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
        // The receipts and earnings buttons that were here are gone: history and
        // earnings are drawer destinations now, and two identical-looking icon
        // buttons in a navbar nobody labelled is not a place to keep them.
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
              detail: 'Ask the branch to add you, then pull down to refresh. '
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
                MrSectionTitle(
                  title: 'Recent deliveries',
                  trailing: TextButton(
                    onPressed: () => context.push(riderHistoryLocation),
                    child: const Text('View all'),
                  ),
                ),
                const SizedBox(height: 12),
                ...history.take(3).map((delivery) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: RiderDeliveryHistoryCard(delivery: delivery),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Lifetime delivery count.
///
/// Deliberately no money figure. Riders are paid a fixed monthly salary by the
/// branch, so a per-delivery rate times a count is a number nobody agreed to
/// and that the branch cannot honour. Only the count, which is a fact.
class _TotalsStrip extends ConsumerWidget {
  const _TotalsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(riderDeliveriesProvider);
    final completed = countAsync.valueOrNull == null
        ? null
        : completedCountFor(countAsync.valueOrNull!);

    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Deliveries completed (all time)',
            value: completed == null ? '—' : '$completed',
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
    final secondaryAction = secondaryActionFor(delivery);
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
                onPressed:
                    busy ? null : () => _runAction(context, ref, action.action),
                child: Text(action.label),
              ),
            ),
          ],
          // Second button, only ever "Cash Collected", and only once the job is
          // done and the order was cash. An online order has already been
          // settled by the IPN, so offering to collect it would be nonsense.
          if (secondaryAction != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: busy
                    ? null
                    : () =>
                        _runAction(context, ref, secondaryAction.action),
                child: Text(secondaryAction.label),
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: busy ? null : () => _reportProblem(context, ref),
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
        case RiderAction.collectCash:
          await controller.markCashCollected(delivery.orderId);
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
              Text('New order', style: Theme.of(context).textTheme.labelSmall),
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

  Future<void> _open(
      BuildContext context, Uri uri, String failureMessage) async {
    final opened = await launchUrl(uri);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failureMessage)));
    }
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
Future<void> _guard(
    BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on RiderRepositoryException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}
