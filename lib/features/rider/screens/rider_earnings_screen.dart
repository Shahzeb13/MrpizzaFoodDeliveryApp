import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/widgets.dart';
import '../providers/rider_providers.dart';

/// Payout earned so far, at the store's configured rate per delivery.
///
/// The rate lives in `store_settings` rather than in code. When it cannot be
/// read the screen says so rather than showing a zero, because a rider cannot
/// tell a real zero from a missing rate and a zero looks like a pay problem.
class RiderEarningsScreen extends ConsumerWidget {
  const RiderEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earningsAsync = ref.watch(riderEarningsProvider);
    final rateAsync = ref.watch(payoutRateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Earnings')),
      body: earningsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text('Could not load your earnings.',
                textAlign: TextAlign.center),
          ),
        ),
        data: (earnings) {
          final rate = rateAsync.valueOrNull ?? 0;
          if (rate <= 0) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Your payout rate is unavailable, so totals cannot be shown. '
                  'Ask the branch to confirm it.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(riderEarningsProvider);
              await ref.read(riderEarningsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                const MrSectionTitle(title: 'Earnings so far'),
                const SizedBox(height: 14),
                MrCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rs. ${earnings.toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'At Rs. ${rate.toStringAsFixed(0)} per delivery',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
