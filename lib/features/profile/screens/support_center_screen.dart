import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';
import '../models/support_document.dart';

/// Contact options plus the policies and FAQs the business publishes.
///
/// The policy pages are not written out here. They are read from the website in
/// a WebView, so the customer always sees the currently published terms and the
/// shop can change a refund rule without an app release. Nothing on this screen
/// restates a rule in its own words.
class SupportCenterScreen extends StatelessWidget {
  const SupportCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Support Center'),
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
            // Contact Action Cards
            Row(
              children: [
                Expanded(
                  child: _buildContactCard(
                    context,
                    icon: Icons.phone_in_talk_rounded,
                    title: 'Call Us',
                    subtitle: '+92 331 6290108',
                    color: AppColors.success,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Calling Mr. Pizza Helpline...')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildContactCard(
                    context,
                    icon: Icons.chat_rounded,
                    title: 'WhatsApp Chat',
                    subtitle: '24/7 Available',
                    color: AppColors.primary,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Opening WhatsApp Support...')),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),

            const MrSectionTitle(
              title: 'Policies & Information',
              eyebrow: 'Legal',
            ),
            const SizedBox(height: 14),

            ...SupportDocument.values
                .map((document) => _buildDocumentRow(context, document)),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentRow(BuildContext context, SupportDocument document) {
    return MrCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/support/document/${document.slug}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            MrIconWell(icon: _iconFor(document), size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                document.label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textLight,
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(SupportDocument document) {
    switch (document) {
      case SupportDocument.termsAndConditions:
        return Icons.description_outlined;
      case SupportDocument.privacyPolicy:
        return Icons.lock_outline_rounded;
      case SupportDocument.returnPolicy:
        return Icons.assignment_return_outlined;
      case SupportDocument.refundPolicy:
        return Icons.currency_exchange_rounded;
      case SupportDocument.faqs:
        return Icons.help_outline_rounded;
    }
  }

  Widget _buildContactCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return MrCard(
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Column(
        children: [
          MrIconWell(
            icon: icon,
            color: color,
            background: color.withValues(alpha: 0.12),
            size: 24,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
