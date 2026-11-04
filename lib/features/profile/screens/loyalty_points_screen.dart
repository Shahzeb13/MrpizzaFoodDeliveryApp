import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/neumorphic.dart';
import '../../loyalty/models/loyalty.dart';
import '../../loyalty/providers/loyalty_provider.dart';
import '../../loyalty/widgets/spend_points_control.dart';

/// The customer's real points balance and the ledger behind it matching Image 4.
class LoyaltyPointsScreen extends ConsumerWidget {
  const LoyaltyPointsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(loyaltyBalanceProvider);

    return Scaffold(
      backgroundColor: NeuColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Loyalty Points',
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
            onPressed: () => Navigator.of(context).canPop()
                ? Navigator.of(context).pop()
                : context.go('/home'),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: NeuColors.textPrimary,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () => ref.read(loyaltyBalanceProvider.notifier).reload(),
            child: balanceAsync.when(
              loading: () => const _LoadingBody(),
              error: (_, __) => const _LoadingBody(),
              data: (balance) => _buildContent(context, balance),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, LoyaltyBalance balance) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _BalanceCard(balance: balance),
        const SizedBox(height: 24),
        NeuPillBadge(
          label: 'EVERY MOVEMENT',
          textColor: NeuColors.primary,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Activity',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: NeuColors.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
            const Text(
              'Last 14 days',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: NeuColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (balance.history.isEmpty)
          _buildEmptyHistory(context, balance)
        else
          ...balance.history.map(_HistoryRow.new),
      ],
    );
  }

  Widget _buildEmptyHistory(BuildContext context, LoyaltyBalance balance) {
    final earnRate = balance.settings.earnRateLabel;
    return NeuCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: NeuColors.primary,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4DE51926),
                  blurRadius: 10,
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
                  earnRate ?? 'No points yet',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: NeuColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Points are added automatically once an order is delivered. Nothing to claim, and nothing to remember.',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 12,
                    color: NeuColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The dark balance card matching Image 4.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final LoyaltyBalance balance;

  @override
  Widget build(BuildContext context) {
    final earnRate = balance.settings.earnRateLabel ?? 'EARN 1 POINT FOR EVERY RS 20';
    final redemptionRate = balance.settings.redemptionRateLabel ?? '1 point = Rs 0.5';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: NeuColors.primary,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x80E51926),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.star_outline_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            formatPoints(balance.balance),
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Available Pizza Points',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB0B3BA),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: NeuColors.primary,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66E51926),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              earnRate.toUpperCase(),
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Worth $redemptionRate when you spend them',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: Color(0xFF9EA3AE),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// One ledger row matching Image 4 with red square (+) or soft debossed (-) icon.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.entry);

  final LoyaltyEntry entry;

  @override
  Widget build(BuildContext context) {
    final isDeduction = entry.isDeduction;
    final sign = isDeduction ? '-' : '+';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NeuCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        borderRadius: BorderRadius.circular(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (!isDeduction)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: NeuColors.primary,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66E51926),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
              )
            else
              NeuInset(
                borderRadius: BorderRadius.circular(14),
                padding: const EdgeInsets.all(10),
                child: const SizedBox(
                  width: 24,
                  height: 24,
                  child: Center(
                    child: Icon(
                      Icons.remove_rounded,
                      color: NeuColors.textPrimary,
                      size: 20,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: NeuColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _timestampLabel(entry.createdAt),
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
            const SizedBox(width: 10),
            Text(
              '$sign${formatPoints(entry.points.abs())}',
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: NeuColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

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

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: const Color(0xFF16161A),
            borderRadius: BorderRadius.circular(28),
          ),
          child: const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: NeuColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 26),
        const Center(
          child: Text(
            'Loading your points',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: NeuColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}