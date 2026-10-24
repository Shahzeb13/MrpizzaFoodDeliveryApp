import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';
import '../models/rider_delivery.dart';

/// A finished delivery: one line until tapped, then the order details.
///
/// Shared by the dashboard's "Recent deliveries" peek and the full "My
/// Deliveries" list, so both open the same way. The expanded part is what a
/// rider can still need after the job ends: where it went, what was in the bag,
/// which branch it came from and how it was paid.
class RiderDeliveryHistoryCard extends StatefulWidget {
  const RiderDeliveryHistoryCard({
    super.key,
    required this.delivery,
  });

  final RiderDelivery delivery;

  @override
  State<RiderDeliveryHistoryCard> createState() =>
      _RiderDeliveryHistoryCardState();
}

class _RiderDeliveryHistoryCardState extends State<RiderDeliveryHistoryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final delivery = widget.delivery;
    final delivered = delivery.assignmentStatus == 'delivered';

    return MrCard(
      onTap: () => setState(() => _expanded = !_expanded),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(delivery.billNumber,
                        style: Theme.of(context).textTheme.titleSmall),
                    if (delivery.customerName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(delivery.customerName,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              Text(
                delivery.assignmentStatus,
                style: TextStyle(
                  color:
                      delivered ? AppColors.success : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20, color: AppColors.textLight),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: _expanded
                ? _RiderDeliveryHistoryDetails(delivery: delivery)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _RiderDeliveryHistoryDetails extends StatelessWidget {
  const _RiderDeliveryHistoryDetails({required this.delivery});

  final RiderDelivery delivery;

  @override
  Widget build(BuildContext context) {
    final payment = _paymentLabel(delivery);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          if (delivery.deliveryAddress.isNotEmpty) ...[
            _DetailLine(
              icon: Icons.location_on_rounded,
              text: delivery.deliveryAddress,
            ),
            const SizedBox(height: 8),
          ],
          if (delivery.itemSummary.isNotEmpty) ...[
            _DetailLine(
              icon: Icons.shopping_bag_rounded,
              text: delivery.itemSummary,
            ),
            const SizedBox(height: 8),
          ],
          if (delivery.itemCount > 0) ...[
            _DetailLine(
              icon: Icons.receipt_long_rounded,
              text: '${delivery.itemCount} '
                  'item${delivery.itemCount == 1 ? '' : 's'}',
            ),
            const SizedBox(height: 8),
          ],
          _DetailLine(
            icon: Icons.storefront_rounded,
            text: 'Collect from ${delivery.branchName}',
          ),
          if (payment != null) ...[
            const SizedBox(height: 8),
            _DetailLine(
              icon: Icons.payments_rounded,
              text: payment,
            ),
          ],
        ],
      ),
    );
  }

  /// The money line, or null when the order predates payment methods.
  String? _paymentLabel(RiderDelivery delivery) {
    switch (delivery.paymentMethod) {
      case 'cod':
        return delivery.paymentStatus == 'paid'
            ? 'Cash on delivery · collected'
            : 'Cash on delivery · not collected';
      case 'online':
        return 'Paid online';
      default:
        return null;
    }
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppColors.textLight),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}
