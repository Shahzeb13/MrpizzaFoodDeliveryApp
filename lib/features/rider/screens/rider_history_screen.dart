import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/rider_providers.dart';
import '../widgets/rider_delivery_history_card.dart';

/// Every delivery this rider has finished, newest first.
///
/// The list arrives one page at a time so a rider with a long history does not
/// wait for, or hold, all of it at once. Tapping a row opens its details.
class RiderHistoryScreen extends ConsumerWidget {
  const RiderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(riderHistoryControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Deliveries')),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _HistoryMessage(
          message: 'Could not load your deliveries.',
          onRetry: () => ref.invalidate(riderHistoryControllerProvider),
        ),
        data: (history) {
          if (history.deliveries.isEmpty) {
            return const _HistoryMessage(
              message: 'No completed deliveries yet',
              detail: 'Orders you finish will be listed here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(riderHistoryControllerProvider.notifier).refresh(),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: history.deliveries.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == history.deliveries.length) {
                  return _HistoryFooter(state: history);
                }
                return RiderDeliveryHistoryCard(
                    delivery: history.deliveries[index]);
              },
            ),
          );
        },
      ),
    );
  }
}

/// The end of the list, or the button that asks for the next page.
class _HistoryFooter extends ConsumerWidget {
  const _HistoryFooter({required this.state});

  final RiderHistoryState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!state.hasMore) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Center(
          child: Text(
            'That is every delivery.',
            style: TextStyle(fontSize: 12, color: AppColors.textLight),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: OutlinedButton(
        onPressed: state.isLoadingMore ? null : () => _loadMore(context, ref),
        child: state.isLoadingMore
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Load more'),
      ),
    );
  }

  Future<void> _loadMore(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(riderHistoryControllerProvider.notifier).loadMore();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load more deliveries.')),
      );
    }
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
