/// How a customer is paying for an order.
library;

/// The choice is made on `/payment-method` and handed back to checkout, which
/// places the order. The order row is only written once one of these is picked —
/// nothing exists before then, so backing out of the page leaves no order, no
/// kitchen ticket and no voucher claimed.
enum PaymentChoice {
  /// PayFast's hosted page in a WebView. The order is marked paid only when the
  /// IPN comes back through `payfast-ipn`; the app never decides that itself.
  online('Online Payment'),

  /// Hand the rider the cash. Nothing marks this order paid automatically — the
  /// rider marks it collected on delivery, which is why it sits at 'pending'
  /// until then rather than being written off as unpaid.
  cashOnDelivery('Cash on Delivery');

  final String label;
  const PaymentChoice(this.label);
}
