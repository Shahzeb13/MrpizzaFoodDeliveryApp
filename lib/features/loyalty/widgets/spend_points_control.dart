import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/widgets.dart';
import '../models/loyalty.dart';
import '../providers/loyalty_provider.dart';

/// Groups a point count so a four-figure balance does not read as noise.
String formatPoints(int points) {
  final digits = points.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  final grouped = buffer.toString();
  return points < 0 ? '-$grouped' : grouped;
}

/// The "spend my points" control on checkout.
///
/// The saving is labelled a ceiling, not a total, because it is applied by the
/// database only once the order exists: the function clamps the request to what
/// the order can actually absorb and rounds it down to whole points, so the
/// figure this screen shows is the most the customer could get, and the real one
/// arrives in the response. The order total shown elsewhere on checkout is
/// therefore left exactly as it was — pretending to have already deducted a
/// discount that has not been granted would be the one number that can disagree
/// with the till.
class SpendPointsControl extends ConsumerWidget {
  const SpendPointsControl({
    super.key,
    required this.points,
    required this.onChanged,
  });

  final int points;
  final ValueChanged<int> onChanged;

  /// The most that can be asked for: the whole balance.
  ///
  /// Bounded by the balance only. How much of it this particular order can
  /// absorb is the database's decision, and asking for more than that is allowed
  /// — it comes back clamped.
  int _maxSpendable(int balance) => balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(loyaltyBalanceProvider);

    return MrCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(18),
      color: balanceAsync.isLoading ? null : AppColors.surface,
      child: balanceAsync.when(
        loading: () => const _ControlSkeleton(),
        error: (_, __) => const _ControlMessage(
          icon: Icons.stars_rounded,
          title: 'Points unavailable',
          detail: 'We could not load your points right now. You can still '
              'place this order without using them.',
        ),
        data: (loyalty) => _buildBody(context, loyalty),
      ),
    );
  }

  Widget _buildBody(BuildContext context, LoyaltyBalance loyalty) {
    if (!loyalty.canSpendPoints) {
      // The switch is the admin's, so the reason is stated rather than the
      // control simply going missing — a customer who has read about points
      // deserves to be told they are switched off, not left wondering where the
      // feature went.
      final reason = loyalty.settings.enabled
          ? 'The shop has not set a points rate yet, so points cannot be spent.'
          : 'Spending points is switched off at the moment. Points you earn '
              'are still yours and will be here when it is back.';
      return _ControlMessage(
        icon: Icons.stars_rounded,
        title: 'Use your points',
        detail: reason,
      );
    }

    if (!loyalty.hasPoints) {
      // Empty state: an earn rate is the useful thing to show, not an apology.
      return _ControlMessage(
        icon: Icons.stars_rounded,
        title: loyalty.settings.earnRateLabel ??
            'Points earn as you order',
        detail: 'Points land in your account once an order is delivered, and '
            'you can spend them on the next one.',
      );
    }

    final maxSpendable = _maxSpendable(loyalty.balance);
    final selected = points.clamp(0, maxSpendable);
    final conversion = loyalty.settings.redemptionRateLabel;
    final upperBound = selected * (loyalty.settings.redemptionValue ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const MrIconWell(icon: Icons.stars_rounded, color: AppColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Use your points',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatPoints(loyalty.balance)} available${conversion == null ? '' : ' · $conversion'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              onPressed: selected <= 0
                  ? null
                  : () => onChanged(_step(selected, -1, maxSpendable)),
            ),
            Expanded(
              child: Center(
                child: Text(
                  formatPoints(selected),
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            _StepButton(
              icon: Icons.add_rounded,
              onPressed: selected >= maxSpendable
                  ? null
                  : () => onChanged(_step(selected, 1, maxSpendable)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                selected == 0
                    ? 'None selected'
                    : 'Up to Rs ${upperBound.toInt()} off this order',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected == 0
                          ? AppColors.textSecondary
                          : AppColors.success,
                      fontWeight: selected == 0 ? FontWeight.w500 : FontWeight.w700,
                    ),
              ),
            ),
            if (selected != maxSpendable)
              TextButton(
                onPressed: () => onChanged(maxSpendable),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Use all'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 14, color: AppColors.textLight),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Applied to your total as soon as you place the order. The '
                'order cannot be refunded in points once it is on its way.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.textLight, fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Moves the selection, clamped to what is actually available.
  int _step(int current, int delta, int maxSpendable) {
    final next = current + delta;
    if (next < 0) return 0;
    if (next > maxSpendable) return maxSpendable;
    return next;
  }
}

/// One half of the stepper. Big enough to hit with a thumb.
class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 48,
          height: 44,
          decoration: BoxDecoration(
            color: onPressed == null ? AppColors.sand : AppColors.primaryTint,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            size: 20,
            color: onPressed == null ? AppColors.textLight : AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _ControlMessage extends StatelessWidget {
  const _ControlMessage({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MrIconWell(icon: icon, color: AppColors.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// A fixed-height placeholder so the control does not collapse and then jump
/// when the balance lands.
class _ControlSkeleton extends StatelessWidget {
  const _ControlSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 76,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}