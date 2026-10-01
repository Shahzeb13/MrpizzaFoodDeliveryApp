import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/orders/models/order_tracking.dart';
import 'package:mrpizza/features/orders/presentation/live_order_visibility.dart';

/// The live order bar's entire behaviour is these rules. Everything else around
/// it is animation, and the rules are what decide whether a customer is told
/// their order was cancelled or quietly never told at all — so they are pinned
/// down here rather than left to be verified by watching a widget.
void main() {
  const orderId = '11111111-1111-1111-1111-111111111111';
  final now = DateTime(2026, 9, 29, 14, 15);

  OrderTracking orderWithStatus(String status) {
    return OrderTracking(
      orderId: orderId,
      billNumber: 'MP-ABT-00042',
      status: status,
      orderType: 'delivery',
      subtotal: 2450,
      tax: 196,
      deliveryCharges: 150,
      discountAmount: 300,
      total: 2496,
      createdAt: DateTime(2026, 9, 29, 14, 15),
      deliveryAddress: 'House 12, Street 4, Mandian, Abbottabad',
      branchName: 'Mr. Pizza - Abbottabad',
      items: const [],
      rider: null,
      timeline: const [],
    );
  }

  LiveOrderVisibility resolve({
    String? status = 'in_kitchen',
    LiveOrderConclusion? conclusion,
    bool isLoading = false,
    bool hasError = false,
    DateTime? at,
    Duration delay = liveOrderDeliveredAutoHideDelay,
  }) {
    return resolveLiveOrderVisibility(
      tracking: status == null ? null : orderWithStatus(status),
      isLoading: isLoading,
      hasError: hasError,
      conclusion: conclusion,
      now: at ?? now,
      deliveredAutoHideDelay: delay,
    );
  }

  group('an order that is still moving', () {
    test('is shown for every stage between placed and delivered', () {
      expect(resolve(status: 'confirmed'), LiveOrderVisibility.active);
      expect(resolve(status: 'in_kitchen'), LiveOrderVisibility.active);
      expect(resolve(status: 'ready_for_pickup'), LiveOrderVisibility.active);
      expect(resolve(status: 'out_for_delivery'), LiveOrderVisibility.active);
    });

    test('stays up no matter how long ago it was recorded', () {
      // A conclusion left over from an earlier order must never hide an order
      // that is still cooking.
      expect(
        resolve(
          status: 'in_kitchen',
          conclusion: LiveOrderConclusion(
            firstShownTerminalAt: now.subtract(const Duration(hours: 9)),
          ),
        ),
        LiveOrderVisibility.active,
      );
    });
  });

  group('a delivered order leaves on its own', () {
    test('is shown once the bar first paints it', () {
      expect(resolve(status: 'delivered'), LiveOrderVisibility.delivered);
    });

    test('is still shown just before the auto-hide delay', () {
      expect(
        resolve(
          status: 'delivered',
          conclusion: LiveOrderConclusion(firstShownTerminalAt: now),
          at: now.add(const Duration(seconds: 59)),
        ),
        LiveOrderVisibility.delivered,
      );
    });

    test('is gone once the delay has passed', () {
      expect(
        resolve(
          status: 'delivered',
          conclusion: LiveOrderConclusion(firstShownTerminalAt: now),
          at: now.add(const Duration(seconds: 60)),
        ),
        LiveOrderVisibility.hidden,
      );
    });

    test('does not blink out before the bar has painted it', () {
      // No record yet means "the bar is about to show it". Hiding for one frame
      // would be a flicker, and the record lands on the frame after the paint.
      expect(
        resolve(status: 'delivered', conclusion: null),
        LiveOrderVisibility.delivered,
      );
    });

    test('a clock that jumped backwards does not hide it early', () {
      expect(
        resolve(
          status: 'delivered',
          conclusion: LiveOrderConclusion(
            firstShownTerminalAt: now.add(const Duration(minutes: 5)),
          ),
        ),
        LiveOrderVisibility.delivered,
      );
    });
  });

  group('a cancelled order waits to be acknowledged', () {
    test('is shown even long after it happened', () {
      // The deliberate contrast with delivery: this is the one status a
      // customer must not have time out of their view.
      expect(
        resolve(
          status: 'cancelled',
          conclusion: LiveOrderConclusion(
            firstShownTerminalAt: now.subtract(const Duration(days: 3)),
          ),
          at: now.add(const Duration(days: 3)),
        ),
        LiveOrderVisibility.cancelled,
      );
    });

    test('is shown before the bar has recorded anything', () {
      expect(resolve(status: 'cancelled'), LiveOrderVisibility.cancelled);
    });

    test('is gone only once the customer dismisses it', () {
      expect(
        resolve(
          status: 'cancelled',
          conclusion: LiveOrderConclusion(
            firstShownTerminalAt: now,
            dismissedAt: now,
          ),
        ),
        LiveOrderVisibility.hidden,
      );
    });

    test('ignores the delivery auto-hide delay entirely', () {
      expect(
        resolve(
          status: 'cancelled',
          conclusion: LiveOrderConclusion(firstShownTerminalAt: now),
          at: now.add(const Duration(minutes: 30)),
          delay: const Duration(seconds: 1),
        ),
        LiveOrderVisibility.cancelled,
      );
    });
  });

  group('nothing to show is nothing to show', () {
    test('a customer with no order sees no bar', () {
      expect(resolve(status: null), LiveOrderVisibility.hidden);
    });

    test('a failed read never surfaces on the home screen', () {
      // The customer came to browse pizza. A tracking outage must not put an
      // error in the middle of that.
      expect(resolve(hasError: true), LiveOrderVisibility.hidden);
      expect(
        resolve(status: 'cancelled', hasError: true),
        LiveOrderVisibility.hidden,
      );
    });

    test('a still-loading read does not flash a half-drawn bar', () {
      expect(resolve(isLoading: true), LiveOrderVisibility.hidden);
    });
  });
}
