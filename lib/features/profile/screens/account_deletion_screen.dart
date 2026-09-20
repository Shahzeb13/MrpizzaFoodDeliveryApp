import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';

class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({super.key});

  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  String selectedReason = 'No longer using the app';
  final List<String> reasons = [
    'No longer using the app',
    'Created a duplicate account',
    'Privacy or security concerns',
    'Too many notifications',
    'Other reason',
  ];

  void _confirmAccountDeletion() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              MrIconWell(
                icon: Icons.warning_amber_rounded,
                color: Color(0xFFB3261E),
                background: Color(0x1FB3261E),
                size: 24,
              ),
              SizedBox(width: 10),
              Text('Delete Account?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ],
          ),
          content: const Text(
            'Are you sure you want to permanently delete your Mr. Pizza account? All your wallet balance and loyalty points will be permanently erased.',
            style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/login');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Account deletion request submitted. Logging out...'),
                    backgroundColor: Color(0xFFB3261E),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB3261E),
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirm Deletion'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Request Account Deletion'),
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
            // Warning Banner
            MrCard(
              padding: const EdgeInsets.all(16),
              borderRadius: BorderRadius.circular(18),
              color: const Color(0x14B3261E),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MrIconWell(
                    icon: Icons.report_problem_rounded,
                    color: Color(0xFFB3261E),
                    background: Color(0x22B3261E),
                    size: 24,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Permanent Action Warning',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: const Color(0xFFB3261E)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Deleting your account is permanent. Saved addresses, order history, loyalty points, and wallet funds will be erased.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                    height: 1.35,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            Text(
              'Please tell us why you are leaving:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),

            RadioGroup<String>(
              groupValue: selectedReason,
              onChanged: (val) {
                if (val != null) {
                  setState(() => selectedReason = val);
                }
              },
              child: Column(
                children: reasons
                    .map((reason) => MrCard(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: EdgeInsets.zero,
                          borderRadius: BorderRadius.circular(14),
                          child: RadioListTile<String>(
                            title: Text(
                              reason,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            value: reason,
                            activeColor: AppColors.primary,
                          ),
                        ))
                    .toList(),
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _confirmAccountDeletion,
                icon: const Icon(Icons.delete_forever_rounded,
                    color: Colors.white),
                label: const Text(
                  'Delete My Account',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB3261E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}