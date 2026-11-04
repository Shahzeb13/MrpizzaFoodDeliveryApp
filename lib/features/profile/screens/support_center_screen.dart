import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/neumorphic.dart';
import '../models/support_document.dart';

/// Contact options, FAQs accordion, and message ticketing matching Image 5.
class SupportCenterScreen extends StatefulWidget {
  const SupportCenterScreen({super.key});

  @override
  State<SupportCenterScreen> createState() => _SupportCenterScreenState();
}

class _SupportCenterScreenState extends State<SupportCenterScreen> {
  final _messageController = TextEditingController();
  int? _expandedFaqIndex;

  final List<Map<String, String>> _faqs = [
    {
      'question': 'How long does pizza delivery take?',
      'answer':
          'Average delivery time is 30–45 minutes depending on traffic and order volume. You can track your order live anytime.',
    },
    {
      'question': 'What are the delivery charges?',
      'answer':
          'Delivery charges are calculated based on your distance from the branch, starting at Rs. 150.',
    },
    {
      'question': 'Can I track my order live?',
      'answer':
          'Yes! Open Live Order Tracking from the drawer or orders tab to see real-time updates as your food is prepared and dispatched.',
    },
    {
      'question': 'What payment methods are supported?',
      'answer':
          'We accept Cash on Delivery (COD), JazzCash, and direct online bank card payments at checkout.',
    },
  ];

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _makeCall(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start a call to $phone')),
        );
      }
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp.')),
        );
      }
    }
  }

  void _submitTicket() {
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe your query or issue first.')),
      );
      return;
    }

    _messageController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your ticket has been submitted! Support will respond shortly.'),
        backgroundColor: Color(0xFF2E7D32),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeuColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'Support Center',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Dual Action Cards
            Row(
              children: [
                Expanded(
                  child: NeuCard(
                    padding: const EdgeInsets.all(18),
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _makeCall('+923316290108'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: NeuColors.primary,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x66E51926),
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.call_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Call Us',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: NeuColors.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          '+92 331 6290108',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: NeuColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: NeuCard(
                    padding: const EdgeInsets.all(18),
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _openWhatsApp('+923316290108'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F1F24),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'WhatsApp Chat',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: NeuColors.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          '24/7 available',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: NeuColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // HELP Pill
            NeuPillBadge(
              label: 'HELP',
              textColor: NeuColors.primary,
            ),
            const SizedBox(height: 10),
            const Text(
              'Frequently asked questions',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: NeuColors.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 14),

            // Accordion FAQs
            ..._faqs.asMap().entries.map((entry) {
              final index = entry.key;
              final faq = entry.value;
              final isExpanded = _expandedFaqIndex == index;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: NeuCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    setState(() {
                      _expandedFaqIndex = isExpanded ? null : index;
                    });
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              faq['question']!,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: NeuColors.textPrimary,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: NeuColors.textPrimary,
                            size: 20,
                          ),
                        ],
                      ),
                      if (isExpanded) ...[
                        const SizedBox(height: 10),
                        Text(
                          faq['answer']!,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 12.5,
                            color: NeuColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 18),
            const Text(
              'Send us a message',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: NeuColors.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 14),

            // Debossed multiline message textarea
            NeuInset(
              borderRadius: BorderRadius.circular(20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: TextField(
                controller: _messageController,
                maxLines: 4,
                cursorColor: NeuColors.primary,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: NeuColors.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText: 'Describe your query or issue..',
                  hintStyle: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 13.5,
                    color: Color(0xFF8A94A6),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Submit Ticket CTA Button
            NeuPrimaryButton(
              onPressed: _submitTicket,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Submit ticket',
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            // Published Legal Documents Link Section
            const Text(
              'Legal & Policies',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: NeuColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: SupportDocument.values.map((doc) {
                return InkWell(
                  onTap: () => context.push('/support/document/${doc.slug}'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: NeuColors.sand,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      doc.label,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: NeuColors.textPrimary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
