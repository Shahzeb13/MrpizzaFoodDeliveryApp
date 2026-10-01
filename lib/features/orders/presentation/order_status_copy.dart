import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../models/order_tracking.dart';

/// Every piece of wording and colour the order status UI needs, in one place.
///
/// The tracking screen and the order list both render the same stages, and the
/// animated header needs the same strings as the pipeline below it. Keeping
/// them here means "Ready for pickup" cannot read one way on the big card and
/// another way in the list, and a new status is added in exactly one place.

/// How many of the five pipeline steps the order has actually finished.
int pipelineProgressFor(OrderStage stage) {
  switch (stage) {
    case OrderStage.orderConfirmed:
      return 0;
    case OrderStage.preparingInKitchen:
      return 1;
    case OrderStage.readyForPickup:
      return 2;
    case OrderStage.riderHeadingToBranch:
    case OrderStage.outForDelivery:
      return 3;
    case OrderStage.delivered:
      return OrderTracking.pipelineStepCount;
    case OrderStage.cancelled:
      return 0;
    case OrderStage.unknown:
      // Deliberately zero, not full. An unknown status has completed no known
      // step, and claiming it finished all five would be a second lie stacked
      // on top of the first.
      return 0;
  }
}

String stageHeadline(OrderStage stage, OrderTracking tracking) {
  switch (stage) {
    case OrderStage.orderConfirmed:
      return 'Order Placed!';
    case OrderStage.preparingInKitchen:
      return 'Preparing Your Food';
    case OrderStage.readyForPickup:
      return 'Ready for Pickup';
    case OrderStage.riderHeadingToBranch:
      return 'Rider On The Way';
    case OrderStage.outForDelivery:
      return 'Out For Delivery!';
    case OrderStage.delivered:
      return 'Delivered!';
    case OrderStage.cancelled:
      return 'Order Cancelled';
    case OrderStage.unknown:
      return 'Status Unavailable';
  }
}

String stageSubtitle(OrderStage stage, OrderTracking tracking) {
  final riderName = tracking.rider?.fullName;
  final who = riderName ?? 'Your rider';

  switch (stage) {
    case OrderStage.orderConfirmed:
      return 'The branch has your order and will start cooking shortly';
    case OrderStage.preparingInKitchen:
      return 'The kitchen is cooking your order now';
    case OrderStage.readyForPickup:
      return 'Your food is packed and waiting for the rider';
    case OrderStage.riderHeadingToBranch:
      return '$who is on the way to collect your order';
    case OrderStage.outForDelivery:
      return '$who is bringing your order to you';
    case OrderStage.delivered:
      return 'Your order has been delivered';
    case OrderStage.cancelled:
      return 'This order was cancelled. Contact the branch if that is unexpected.';
    case OrderStage.unknown:
      return _unknownStatusSubtitle(tracking.status);
  }
}

/// Says the app is behind, and shows the stored value rather than inventing a
/// stage for it.
String _unknownStatusSubtitle(String storedStatus) {
  final stored = storedStatus.trim();
  if (stored.isEmpty) {
    return 'This order has no status saved against it. Tap for details.';
  }
  return 'This order is marked "$stored", which this version of the app does '
      'not understand yet. Tap for details.';
}

/// Plain-English wording for a stored `rider_assignments.status`.
String riderAssignmentLabel(String status) {
  switch (status) {
    case 'assigned':
      return 'Assigned to your order, heading to the branch';
    case 'accepted':
      return 'On the way to collect your order';
    case 'picked_up':
      return 'Has your order and is on the way to you';
    case 'delivered':
      return 'Delivered your order';
    case 'declined':
      return 'Could not take this order';
    case 'failed':
      return 'Could not complete this delivery';
    default:
      return 'Assigned to your order';
  }
}

/// Plain-English wording for a stored `orders.status` or
/// `order_status_history.status`.
String statusLabel(String status) {
  switch (status) {
    case 'confirmed':
      return 'Order confirmed';
    case 'in_kitchen':
      return 'Preparing in the kitchen';
    case 'ready_for_pickup':
      return 'Ready for pickup';
    case 'out_for_delivery':
      return 'Out for delivery';
    case 'delivered':
      return 'Delivered';
    case 'cancelled':
      return 'Cancelled';
    default:
      // Shown as stored rather than forced into a bucket the app invented, so
      // a status added in the database is never silently mistranslated.
      return status;
  }
}

Color stageColorFor(OrderStage stage) {
  switch (stage) {
    case OrderStage.delivered:
      return AppColors.success;
    case OrderStage.cancelled:
      // Was [AppColors.textLight], which is the same muted tan the "this is
      // nothing" colour uses. A cancelled order is not a quiet outcome, it is
      // the one status a customer must not have to look for, so it is given a
      // real colour instead of disappearing into the background.
      return AppColors.danger;
    case OrderStage.orderConfirmed:
    case OrderStage.preparingInKitchen:
    case OrderStage.readyForPickup:
      return AppColors.warning;
    case OrderStage.riderHeadingToBranch:
    case OrderStage.outForDelivery:
      return AppColors.primary;
    case OrderStage.unknown:
      // Neutral on purpose. Amber means "early stage, sit tight" and red means
      // "something went wrong"; neither is true, and colouring this would make
      // a gap in our own knowledge look like news about the customer's food.
      return AppColors.textLight;
  }
}

/// The icon that goes with a stage on the persistent live bar.
IconData stageIconFor(OrderStage stage) {
  switch (stage) {
    case OrderStage.orderConfirmed:
      return Icons.receipt_long_rounded;
    case OrderStage.preparingInKitchen:
      return Icons.local_fire_department_rounded;
    case OrderStage.readyForPickup:
      return Icons.takeout_dining_rounded;
    case OrderStage.riderHeadingToBranch:
      return Icons.directions_bike_rounded;
    case OrderStage.outForDelivery:
      return Icons.delivery_dining_rounded;
    case OrderStage.delivered:
      return Icons.check_circle_rounded;
    case OrderStage.cancelled:
      return Icons.cancel_rounded;
    case OrderStage.unknown:
      return Icons.help_outline_rounded;
  }
}

String formatClockTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final suffix = time.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $suffix';
}

String formatDayLabel(DateTime time) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final month = months[time.month - 1];
  return '${time.day} $month';
}
