import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';
// wallet
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  double balance = 0.00;

  final List<Map<String, dynamic>> transactions = [
    {
      'title': 'Welcome Bonus Credit',
      'date': '12 Sep 2026, 10:30 AM',
      'amount': '+ Rs. 0.00',
      'type': 'credit',
    },
  ];

  void _addFunds(double amount) {
    setState(() {
      balance += amount;
      transactions.insert(0, {
        'title': 'Top Up Wallet',
        'date': 'Just Now',
        'amount': '+ Rs. ${amount.toStringAsFixed(2)}',
        'type': 'credit',
      });
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Successfully added Rs. ${amount.toStringAsFixed(0)} to wallet!'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Balance Card
            MrDoubleBezel(
              radius: 26,
              innerColor: AppColors.surfaceDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Balance',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textLight),
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
                    'Rs. ${balance.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.displaySmall
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
            ),
            const SizedBox(height: 26),

            // Top Up Quick Actions
            const MrSectionTitle(title: 'Quick Top Up'),
            const SizedBox(height: 14),
            Row(
              children: [500, 1000, 2000].map((amt) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      onPressed: () => _addFunds(amt.toDouble()),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        foregroundColor: AppColors.primary,
                      ),
                      child: Text(
                        'Rs. $amt',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 28),

            const MrSectionTitle(
              title: 'Recent Transactions',
              eyebrow: 'Activity',
            ),
            const SizedBox(height: 14),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: transactions.length,
              itemBuilder: (context, index) {
                final item = transactions[index];
                final isCredit = item['type'] == 'credit';
                return MrCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  borderRadius: BorderRadius.circular(16),
                  child: Row(
                    children: [
                      MrIconWell(
                        icon: isCredit
                            ? Icons.add_card_rounded
                            : Icons.send_rounded,
                        color: isCredit
                            ? AppColors.success
                            : AppColors.primary,
                        background: isCredit
                            ? const Color(0xFFE4F1E8)
                            : AppColors.primaryTint,
                        size: 18,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title'] as String,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item['date'] as String,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        item['amount'] as String,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: isCredit
                                  ? AppColors.success
                                  : AppColors.textPrimary,
                            ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}