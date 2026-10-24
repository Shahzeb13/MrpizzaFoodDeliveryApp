import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    this.enabled = true,
    this.disabledReason,
  });

  final int points;
  final ValueChanged<int> onChanged;

  /// False when something else already owns the order's single saving. The
  /// control then explains itself instead of going grey and silent, because a
  /// locked control with no reason reads as a bug.
  final bool enabled;

  /// Why [enabled] is false. Supplied by the caller that knows the answer — the
  /// words "a voucher is applied" mean nothing inside this widget.
  final String? disabledReason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(loyaltyBalanceProvider);

    return MrCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(18),
      child: !enabled
          ? _ControlMessage(
              icon: Icons.lock_outline_rounded,
              title: 'Use your points',
              detail: disabledReason ??
                  'Points cannot be used on this order right now.',
            )
          : balanceAsync.when(
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

    final maxSpendable = loyalty.balance;
    final conversion = loyalty.settings.redemptionRateLabel;
    final redemptionValue = loyalty.settings.redemptionValue ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const MrIconWell(
                icon: Icons.stars_rounded, color: AppColors.accent),
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
                    '${formatPoints(maxSpendable)} available${conversion == null ? '' : ' · $conversion'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _PointsStepper(
          points: points,
          maxSpendable: maxSpendable,
          onChanged: onChanged,
        ),
        const SizedBox(height: 12),
        _PreviewRow(
          points: points,
          maxSpendable: maxSpendable,
          redemptionValue: redemptionValue,
          onUseAll: () => onChanged(maxSpendable),
          onClear: () => onChanged(0),
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
                'Tap the number to type how many you want. Applied to your '
                'total as soon as you place the order.',
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
}

/// The number, the minus button, the plus button, and a way to just type it.
///
/// Typing matters because the stepper's step size is a guess. A customer with
/// 2,257 points who wants to spend exactly 100 should not have to press a button
/// 100 times to get there, so the figure is a real text field they can tap and
/// type into, with the buttons kept for nudging it by one.
class _PointsStepper extends StatefulWidget {
  const _PointsStepper({
    required this.points,
    required this.maxSpendable,
    required this.onChanged,
  });

  final int points;
  final int maxSpendable;
  final ValueChanged<int> onChanged;

  @override
  State<_PointsStepper> createState() => _PointsStepperState();
}

class _PointsStepperState extends State<_PointsStepper> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.text = _textFor(widget.points);
  }

  @override
  void didUpdateWidget(covariant _PointsStepper oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only pull from the parent when the change did not come from this field.
    // Rewriting the text under the customer's cursor mid-keystroke moves the
    // caret to the end and drops what they were in the middle of typing.
    if (widget.points == oldWidget.points) return;
    if (_focus.hasFocus) return;

    final next = _textFor(widget.points);
    if (_controller.text != next) _controller.text = next;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _textFor(int value) => value <= 0 ? '' : value.toString();

  /// What the field currently shows, clamped for the preview but without
  /// rewriting the text — so a customer part-way through typing 250 is not
  /// fighting a formatter that keeps resetting their caret.
  int get _previewValue {
    final typed = int.tryParse(_controller.text.trim());
    if (typed == null) return 0;
    if (typed < 0) return 0;
    if (typed > widget.maxSpendable) return widget.maxSpendable;
    return typed;
  }

  /// Commits whatever was typed, clamped to what the customer actually holds.
  void _commit() {
    final typed = int.tryParse(_controller.text.trim()) ?? 0;
    final clamped = typed.clamp(0, widget.maxSpendable);
    _controller.text = _textFor(clamped);
    widget.onChanged(clamped);
  }

  void _step(int delta) {
    final next = (_previewValue + delta).clamp(0, widget.maxSpendable);
    _controller.text = _textFor(next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepButton(
          icon: Icons.remove_rounded,
          onPressed: _previewValue <= 0 ? null : () => _step(-1),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(signed: false),
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              // Plain digits, deliberately ungrouped: a comma inside the field
              // is not something `digitsOnly` will let the customer type, and
              // stripping it on the next keystroke moves the caret. The grouped
              // figure is shown underneath instead.
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '0',
                hintStyle: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textLight,
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _commit(),
              onTapOutside: (_) {
                _commit();
                _focus.unfocus();
              },
              onEditingComplete: _commit,
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add_rounded,
          onPressed: _previewValue >= widget.maxSpendable
              ? null
              : () => _step(1),
        ),
      ],
    );
  }
}

/// What the chosen number is worth, plus the shortcuts.
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.points,
    required this.maxSpendable,
    required this.redemptionValue,
    required this.onUseAll,
    required this.onClear,
  });

  final int points;
  final int maxSpendable;
  final double redemptionValue;
  final VoidCallback onUseAll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    // Always worded as a ceiling: the database may clamp the request lower.
    final upperBound = points * redemptionValue;

    return Row(
      children: [
        Expanded(
          child: Text(
            points == 0
                ? 'None selected'
                : '${formatPoints(points)} points · up to '
                    'Rs ${upperBound.toInt()} off this order',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: points == 0
                      ? AppColors.textSecondary
                      : AppColors.success,
                  fontWeight:
                      points == 0 ? FontWeight.w500 : FontWeight.w700,
                ),
          ),
        ),
        if (points != 0)
          _ShortcutButton(label: 'None', onTap: onClear),
        if (points != maxSpendable) ...[
          if (points != 0) const SizedBox(width: 4),
          _ShortcutButton(label: 'Use all', onTap: onUseAll),
        ],
      ],
    );
  }
}

/// A small "Use all" / "None" chip.
class _ShortcutButton extends StatelessWidget {
  const _ShortcutButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primaryTint,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
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