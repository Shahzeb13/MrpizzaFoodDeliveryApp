import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';

class SupportCenterScreen extends StatefulWidget {
  const SupportCenterScreen({super.key});

  @override
  State<SupportCenterScreen> createState() => _SupportCenterScreenState();
}

class _SupportCenterScreenState extends State<SupportCenterScreen> {
  final List<Map<String, String>> faqs = [
    {
      'question': 'How long does pizza delivery take?',
      'answer':
          'We deliver hot & fresh pizza within 30 to 45 minutes of order placement.',
    },
    {
      'question': 'What are the delivery charges?',
      'answer':
          'Free delivery on orders above Rs. 1000! Standard delivery charge is Rs. 99.',
    },
    {
      'question': 'Can I track my order live?',
      'answer':
          'Yes! You can track your order status in real-time under "My Orders" -> "Track Order".',
    },
    {
      'question': 'What payment methods are supported?',
      'answer':
          'We support Cash on Delivery (COD), Credit/Debit Card, and Mr. Pizza Wallet.',
    },
  ];

  final messageController = TextEditingController();

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

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
              title: 'Frequently Asked Questions',
              eyebrow: 'Help',
            ),
            const SizedBox(height: 14),

            ...faqs.map((faq) => MrCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: EdgeInsets.zero,
                  borderRadius: BorderRadius.circular(16),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      title: Text(
                        faq['question']!,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      iconColor: AppColors.primary,
                      collapsedIconColor: AppColors.textLight,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            faq['answer']!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                )),

            const SizedBox(height: 26),

            const MrSectionTitle(title: 'Send Us a Message'),
            const SizedBox(height: 14),
            MrCard(
              padding: const EdgeInsets.all(16),
              borderRadius: BorderRadius.circular(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: messageController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Describe your query or issue...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (messageController.text.isNotEmpty) {
                          messageController.clear();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Support ticket submitted! We will contact you shortly.'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      },
                      child: const Text('Submit Ticket'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard({
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