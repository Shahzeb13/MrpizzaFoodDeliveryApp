import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';
import '../logic/delivery_actions.dart';
import '../providers/rider_providers.dart';

/// Every delivery this rider has finished, newest first.
class RiderHistoryScreen extends ConsumerWidget {
  const RiderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveriesAsync = ref.watch(riderDeliveriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Deliveries')),
      body: deliveriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _HistoryMessage(
          message: 'Could not load your deliveries.',
          onRetry: () => ref.invalidate(riderDeliveriesProvider),
        ),
        data: (deliveries) {
          final history = deliveredHistoryFor(deliveries);
          if (history.isEmpty) {
            return const _HistoryMessage(
              message: 'No completed deliveries yet',
              detail: 'Orders you finish will be listed here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(riderDeliveriesProvider);
              await ref.read(riderDeliveriesProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: history.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final delivery = history[index];
                return MrCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      MrIconWell(
                        icon: delivery.assignmentStatus == 'delivered'
                            ? Icons.check_rounded
                            : Icons.close_rounded,
                        color: delivery.assignmentStatus == 'delivered'
                            ? AppColors.success
                            : AppColors.textSecondary,
                        background: delivery.assignmentStatus == 'delivered'
                            ? AppColors.primaryTint
                            : AppColors.sand,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(delivery.billNumber,
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              delivery.customerName.isEmpty
                                  ? delivery.itemSummary
                                  : delivery.customerName,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
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
              },
            ),
          );
        },
      ),
    );
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.message,
    this.detail,
    this.onRetry,
  });

  final String message;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(detail!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
