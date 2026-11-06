import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/support_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/neumorphic.dart';
import '../models/support_document.dart';

/// Contact options, support hours, FAQs accordion, and the published policy
/// pages.
///
/// Every action on this screen comes from `support_config.dart` — the two
/// branches, the shared email and the support-hours text — so a number or an
/// address changes in one file and nowhere else. The hours are shown as plain
/// text only: the screen never computes an "open now"/"closed" claim from
/// them, because restaurant hours change at short notice and a wrong badge is
/// worse than no badge.
class SupportCenterScreen extends StatefulWidget {
  const SupportCenterScreen({super.key, this.orderReference});

  /// The bill number of the order the customer came from, when this screen
  /// was opened through "Problem with this order?". Prefills the email
  /// subject so every message about one order threads together in the inbox.
  final String? orderReference;

  @override
  State<SupportCenterScreen> createState() => _SupportCenterScreenState();
}

class _SupportCenterScreenState extends State<SupportCenterScreen> {
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

  /// Opens [uri] with whatever app on the phone handles it. When no app can
  /// (no WhatsApp installed, no mail account set up, or the dialler blocked),
  /// the customer is told and offered a one-tap Copy of [copyValue] — the
  /// number or email they were trying to use — instead of a silent failure.
  ///
  /// The messenger is captured before the await, so showing the "Copied"
  /// confirmation never touches a BuildContext across an async gap.
  Future<void> _openExternal(Uri uri, {required String copyValue}) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // url_launcher throws on some devices instead of returning false;
      // both mean "nothing handled it", so both land on the copy fallback.
      opened = false;
    }
    if (opened || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Could not open that. Copy it instead: $copyValue'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Copy',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: copyValue));
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Dials a branch phone. Copy fallback carries the readable number.
  Future<void> _callBranch(SupportBranch branch, String phone) async {
    final index = branch.phones.indexOf(phone);
    final dial = index >= 0 && index < branch.dialUris.length
        ? branch.dialUris[index]
        : Uri(scheme: 'tel', path: SupportBranch.digitsOnly(phone));
    await _openExternal(dial, copyValue: phone);
  }

  /// Opens the branch's WhatsApp chat. Copy fallback carries the number.
  Future<void> _openBranchWhatsApp(SupportBranch branch) => _openExternal(
        Uri.parse(branch.whatsappUrl),
        copyValue: SupportBranch.digitsOnly(branch.whatsappUrl),
      );

  /// Composes the support email with the order number, app version and
  /// platform prefilled. Copy fallback carries the raw email address.
  Future<void> _composeEmail() async {
    final uri = await buildSupportEmailUri(
      orderReference: widget.orderReference,
    );
    await _openExternal(uri, copyValue: supportEmailAddress);
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
          'Help & Support',
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
            // The published hours, shown as text only. Deliberately first:
            // a customer who just missed a reply checks here before anything.
            _buildHoursBanner(),
            const SizedBox(height: 14),

            // One email for both branches; the body carries the app version,
            // platform and — when opened from an order — the order number.
            _buildEmailCard(),
            const SizedBox(height: 24),

            const NeuPillBadge(
              label: 'HELP',
              textColor: NeuColors.primary,
            ),
            const SizedBox(height: 10),
            const Text(
              'Reach a branch directly',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: NeuColors.textPrimary,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 14),
            ...supportBranches.map(
              (branch) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildBranchCard(branch),
              ),
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

            ..._faqs.asMap().entries.map(_buildFaqCard),

            const SizedBox(height: 24),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
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

  Widget _buildHoursBanner() {
    return NeuCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: NeuColors.sand,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              size: 20,
              color: NeuColors.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              supportHoursText,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: NeuColors.textSecondary,
                height: 1.45,
              ),
            ),
          ),        ],
      ),
    );
  }

  Widget _buildEmailCard() {
    return NeuCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 24,
      onTap: _composeEmail,
      child: Row(
        children: [
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
            child: const Icon(
              Icons.mail_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Email us',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 14.5,
                fontWeight: FontWeight.w900,
                color: NeuColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            supportEmailAddress,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: NeuColors.textSecondary,
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: NeuColors.textSecondary,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildBranchCard(SupportBranch branch) {
    return NeuCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            branch.name,
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: NeuColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 16,
                color: NeuColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  branch.address,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: NeuColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: [
              for (final phone in branch.phones)
                _buildActionChip(
                  icon: Icons.call_rounded,
                  label: 'Call $phone',
                  onTap: () => _callBranch(branch, phone),
                ),
              _buildActionChip(
                icon: Icons.chat_bubble_rounded,
                label: 'WhatsApp chat',
                onTap: () => _openBranchWhatsApp(branch),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: NeuColors.sand,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: NeuColors.primary),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: NeuColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqCard(MapEntry<int, Map<String, String>> entry) {
    final index = entry.key;
    final faq = entry.value;
    final isExpanded = _expandedFaqIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NeuCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        borderRadius: 18,
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
  }
}
