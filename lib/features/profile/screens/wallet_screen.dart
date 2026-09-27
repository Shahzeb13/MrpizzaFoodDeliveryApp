import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/widgets.dart';
import '../models/wallet.dart';
import '../providers/wallet_provider.dart';

/// The customer's wallet.
///
/// In-memory only for now: no Supabase writes. The balance is the sum of the
/// ledger in [WalletNotifier] rather than a number on this screen, so it cannot
/// disagree with the transactions underneath it. Topping up takes a confirmation
/// step, the way paying a card does, rather than crediting money on a single tap.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletProvider.notifier);
    final transactions = ref.watch(walletProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Wallet'),
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _BalanceCard(balance: wallet.balance),
          const SizedBox(height: 26),
          const MrSectionTitle(title: 'Add Money'),
          const SizedBox(height: 6),
          const Text(
            'Pick an amount, then confirm to pay.',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          _QuickTopUpRow(
            onPick: (amount) => _openTopUpSheet(context, ref, amount),
          ),
          const SizedBox(height: 28),
          MrSectionTitle(
            title: 'Transactions',
            eyebrow: transactions.isEmpty ? null : '${transactions.length}',
          ),
          const SizedBox(height: 14),
          if (transactions.isEmpty)
            const _NoTransactionsYet()
          else
            ...transactions.map((entry) => _TransactionTile(entry: entry)),
        ],
      ),
    );
  }

  /// Collects the amount and the payment method before any money moves.
  Future<void> _openTopUpSheet(
    BuildContext context,
    WidgetRef ref,
    double amount,
  ) async {
    final wallet = ref.read(walletProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    final method = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => _TopUpSheet(amount: amount),
    );

    if (method == null) return; // customer backed out, nothing happened

    final accepted = wallet.topUp(amount: amount, method: method);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          accepted
              ? 'Added ${formatRupees(amount)} to your wallet via $method.'
              : 'That amount is not allowed. Try between '
                  '${formatRupees(WalletNotifier.minimumTopUp)} and '
                  '${formatRupees(WalletNotifier.maximumTopUp)}.',
        ),
        backgroundColor: accepted ? AppColors.success : AppColors.primary,
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final double balance;

  const _BalanceCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    return MrDoubleBezel(
      radius: 26,
      innerColor: AppColors.surfaceDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Available balance',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textLight),
              ),
              const MrIconWell(
                icon: Icons.account_balance_wallet_rounded,
                color: AppColors.accent,
                background: Color(0x22E3A63B),
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Rs. ${formatRupees(balance)}',
            style: Theme.of(context)
                .textTheme
                .displaySmall
                ?.copyWith(color: Colors.white, fontSize: 30),
          ),
          const SizedBox(height: 16),
          const MrEyebrow(
            text: 'Mr. Pizza Pay Active',
            background: Color(0x2EFFFFFF),
            foreground: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _QuickTopUpRow extends StatelessWidget {
  final ValueChanged<double> onPick;

  const _QuickTopUpRow({required this.onPick});

  @override
  Widget build(BuildContext context) {
    const amounts = [500, 1000, 2000];
    return Row(
      children: [
        for (final amount in amounts)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: amount == amounts.last ? 0 : 8),
              child: OutlinedButton(
                // One tap opens the confirmation sheet. It does not credit
                // anything, which is the whole point.
                onPressed: () => onPick(amount.toDouble()),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  foregroundColor: AppColors.primary,
                ),
                child: Text(
                  'Rs. ${formatRupees(amount.toDouble()).split('.').first}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TopUpSheet extends StatefulWidget {
  final double amount;

  const _TopUpSheet({required this.amount});

  @override
  State<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<_TopUpSheet> {
  static const _methods = <(String, IconData)>[
    ('Card', Icons.credit_card_rounded),
    ('JazzCash', Icons.phone_android_rounded),
    ('EasyPaisa', Icons.account_balance_wallet_rounded),
  ];

  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.borderDeep,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const Text(
            'Confirm top up',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Rs. ${formatRupees(widget.amount)} will be added to your wallet.',
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Pay with',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: AppColors.textLight,
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(_methods.length, (index) {
            final method = _methods[index];
            final isSelected = index == _selected;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _selected = index),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        method.$2,
                        size: 20,
                        color:
                            isSelected ? AppColors.primary : AppColors.textPrimary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          method.$1,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textLight,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.pop(context, _methods[_selected].$1);
              },
              icon: const Icon(Icons.lock_rounded, size: 18, color: Colors.white),
              label: Text(
                'Pay Rs. ${formatRupees(widget.amount).split('.').first}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'This is a demo wallet. No real payment is taken.',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 11.5,
                color: AppColors.textLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final WalletTransaction entry;

  const _TransactionTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isCredit = entry.isCredit;
    return MrCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(16),
      child: Row(
        children: [
          MrIconWell(
            icon: isCredit ? Icons.add_card_rounded : Icons.send_rounded,
            color: isCredit ? AppColors.success : AppColors.primary,
            background:
                isCredit ? const Color(0xFFE4F1E8) : AppColors.primaryTint,
            size: 18,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  entry.subtitle == null
                      ? formatWalletTimestamp(entry.occurredAt)
                      : '${entry.subtitle} · '
                          '${formatWalletTimestamp(entry.occurredAt)}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
          ),
          Text(
            entry.signedLabel,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: isCredit ? AppColors.success : AppColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}

class _NoTransactionsYet extends StatelessWidget {
  const _NoTransactionsYet();

  @override
  Widget build(BuildContext context) {
    return MrCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          const Icon(
            Icons.receipt_long_rounded,
            size: 30,
            color: AppColors.textLight,
          ),
          const SizedBox(height: 10),
          Text(
            'No wallet activity yet',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          const Text(
            'Top up above and it will show up here.',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
