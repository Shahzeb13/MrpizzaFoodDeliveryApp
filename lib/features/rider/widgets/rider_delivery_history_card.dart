import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
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
    // The pill answers one question: did the job END AS A DELIVERY?
    //
    // Only `delivered` is a delivery. Everything else this card can receive is
    // a job that did not complete — `failed` (the rider reported a problem),
    // `declined` (the offer was refused), `cancelled` (the shop released the
    // rider), and any status the card does not recognise. This used to grep the
    // status for 'decline'/'cancel' and fall through to a DELIVERED pill, which
    // reported every problem-order as a finished delivery — the exact lie the
    // rider dashboard must never tell.
    //
    // The matching lifecycle helpers in delivery_actions.dart agree: the
    // completed count and the cash-collect button also accept only the literal
    // `delivered`.
    final isDeclined = delivery.assignmentStatus != 'delivered';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F3F8),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Colors.white,
            offset: Offset(-4, -4),
            blurRadius: 10,
          ),
          BoxShadow(
            color: Color(0x30A6B4C9),
            offset: Offset(4, 4),
            blurRadius: 10,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            delivery.billNumber,
                            style: const TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF141923),
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (delivery.customerName.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              delivery.customerName,
                              style: const TextStyle(
                                fontFamily: 'PlusJakartaSans',
                                fontSize: 13,
                                color: Color(0xFF758295),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Status Pill (DELIVERED or DECLINED)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDeclined
                            ? const Color(0xFF141923)
                            : const Color(0xFFE5EBF3),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: isDeclined
                            ? null
                            : const [
                                BoxShadow(
                                  color: Colors.white,
                                  offset: Offset(-2, -2),
                                  blurRadius: 4,
                                ),
                                BoxShadow(
                                  color: Color(0x1EA6B4C9),
                                  offset: Offset(2, 2),
                                  blurRadius: 4,
                                ),
                              ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isDeclined
                                ? Icons.close_rounded
                                : Icons.check_rounded,
                            size: 13,
                            color: isDeclined
                                ? Colors.white
                                : const Color(0xFFE51926),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isDeclined ? 'DECLINED' : 'DELIVERED',
                            style: TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              color: isDeclined
                                  ? Colors.white
                                  : const Color(0xFFE51926),
                              fontWeight: FontWeight.w900,
                              fontSize: 10.5,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
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
    ),
  ),
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
