import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/widgets.dart';
import '../../loyalty/models/loyalty.dart';
import '../../loyalty/providers/loyalty_provider.dart';
import '../../loyalty/widgets/spend_points_control.dart';

/// The customer's real points balance and the ledger behind it.
///
/// This screen previously invented all of it: an opening balance of 120, a hard
/// coded "Earn 1 point on every Rs. 10", and a list of rewards — a free cold
/// drink, garlic bread, a Rs 300 voucher — that cost points and delivered
/// nothing, because there was no catalogue behind them and no way to honour
/// them. Every figure here is now read from the database, and a customer with
/// no points is told the earn rate instead of being shown something that does
/// not work.
class LoyaltyPointsScreen extends ConsumerWidget {
  const LoyaltyPointsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(loyaltyBalanceProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Loyalty Points'),
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(loyaltyBalanceProvider.notifier).reload(),
        child: balanceAsync.when(
          loading: () => const _LoadingBody(),
          error: (_, __) => const _LoadingBody(),
          data: (balance) => _buildContent(context, balance),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, LoyaltyBalance balance) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _BalanceCard(balance: balance),
        const SizedBox(height: 26),
        MrSectionTitle(
          title: 'Activity',
          eyebrow: 'Every Movement',
          trailing: balance.history.isEmpty
              ? null
              : Text(
                  'Last ${balance.history.length}',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
        ),
        const SizedBox(height: 14),
        if (balance.history.isEmpty)
          _buildEmptyHistory(context, balance)
        else
          ...balance.history.map(_HistoryRow.new),
      ],
    );
  }

  /// No ledger rows is the normal state for a new customer, so this leads with
  /// how to start earning rather than reading as something that failed.
  Widget _buildEmptyHistory(BuildContext context, LoyaltyBalance balance) {
    final earnRate = balance.settings.earnRateLabel;
    return MrCard(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MrIconWell(icon: Icons.stars_rounded, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  earnRate ?? 'No points yet',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Points are added automatically once an order is delivered. '
                  'Nothing to claim, and nothing to remember.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The balance, the rate it earns at, and the rate it is worth.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final LoyaltyBalance balance;

  @override
  Widget build(BuildContext context) {
    final earnRate = balance.settings.earnRateLabel;
    final redemptionRate = balance.settings.redemptionRateLabel;

    return MrDoubleBezel(
      radius: 26,
      innerColor: AppColors.surfaceDark,
      child: Column(
        children: [
          const MrIconWell(
            icon: Icons.stars_rounded,
            color: AppColors.accent,
            background: Color(0x22E3A63B),
            size: 30,
          ),
          const SizedBox(height: 10),
          Text(
            formatPoints(balance.balance),
            style: Theme.of(context)
                .textTheme
                .displayMedium
                ?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            'Available Pizza Points',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textLight),
          ),
          if (earnRate != null) ...[
            const SizedBox(height: 14),
            MrEyebrow(
              text: earnRate,
              background: const Color(0x2EFFFFFF),
              foreground: AppColors.accent,
            ),
          ],
          // The redemption rate is stated next to the balance rather than being
          // implied by it: a customer deciding whether to spend needs to know
          // what a point is worth before they touch the order, not after.
          if (redemptionRate != null) ...[
            const SizedBox(height: 10),
            Text(
              'Worth $redemptionRate when you spend them',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textLight,
                    fontSize: 11,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One ledger row.
///
/// A deduction is drawn in the danger colour, prefixed with a minus, and carries
/// the label "spent" — never the green of a reward. Getting this wrong is how a
/// customer believes they earned Rs 50 and is later told they owe it.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.entry);

  final LoyaltyEntry entry;

  @override
  Widget build(BuildContext context) {
    final isDeduction = entry.isDeduction;
    final accent = isDeduction ? AppColors.danger : AppColors.success;
    final sign = isDeduction ? '-' : '+';

    return MrCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MrIconWell(
            icon: _iconFor(entry),
            color: accent,
            size: 18,
            background: accent.withValues(alpha: 0.10),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  _timestampLabel(entry.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$sign${formatPoints(entry.points.abs())}',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(LoyaltyEntry entry) {
    switch (entry.type) {
      case LoyaltyEntryType.earned:
        return Icons.add_rounded;
      case LoyaltyEntryType.redeemed:
        return Icons.remove_rounded;
      case LoyaltyEntryType.reversed:
        return Icons.undo_rounded;
      case null:
        return entry.isDeduction ? Icons.remove_rounded : Icons.add_rounded;
    }
  }

  /// A ledger row is read in the moment it happened, so a relative time is what
  /// answers "when was this". Past a week the exact time stops mattering and a
  /// date is easier to place.
  static String _timestampLabel(DateTime? when) {
    if (when == null) return '';
    final elapsed = DateTime.now().difference(when);

    if (elapsed.inSeconds < 60) return 'Just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
    if (elapsed.inHours < 24) return '${elapsed.inHours} hr ago';
    if (elapsed.inDays < 7) {
      final days = elapsed.inDays;
      return '$days day${days == 1 ? '' : 's'} ago';
    }

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
    final minute = when.minute.toString().padLeft(2, '0');
    final meridiem = when.hour < 12 ? 'AM' : 'PM';
    return '${when.day} ${months[when.month - 1]}, $hour:$minute $meridiem';
  }
}

/// Keeps the spinner off a blank screen: the card skeleton holds the layout the
/// real content will take.
class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const MrDoubleBezel(
          radius: 26,
          innerColor: AppColors.surfaceDark,
          child: SizedBox(
            height: 150,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 26),
        Center(
          child: Text(
            'Loading your points',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}