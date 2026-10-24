import 'dart:async';

import 'package:flutter/material.dart';
import 'package:payfast_flutter_sdk/payfast_flutter_sdk.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _supabase = Supabase.instance.client;

// Distinct URLs; neither may be a substring of the other (the SDK matches with contains()).
const _successUrl = 'https://mrpizzapak.com/payment/success';
const _failureUrl = 'https://mrpizzapak.com/payment/failure';

// PayFast callback URL. Replace <project-ref>.
const _ipnUrl =
    'https://eytsownrsujphibqpimt.supabase.co/functions/v1/payfast-ipn';

const _isUat = true; // flip to false together with PAYFAST_ENV=live on the backend

/// What the customer did in the payment page.
enum PayfastOutcome {
  /// They reached the success URL. Says nothing about the money — that is the
  /// IPN's job.
  reachedSuccess,

  /// They reached the failure URL, or PayFast reported an error.
  reachedFailure,

  /// They closed the page before either. Very common: half the customers who
  /// open a payment sheet back out of it.
  cancelled,
}

/// Starts a PayFast checkout for an order that has already been placed.
///
/// Every call asks `payfast-token` for a fresh token and basket id. Nothing is
/// cached: a basket id is the primary key of the `payments` table, so reusing
/// one would either collide or mis-match the IPN that comes back.
class PayfastCheckout {
  /// Fetches a token from our backend, opens PayFast's hosted page, and returns
  /// only once that page has closed.
  ///
  /// The SDK's own `RedirectionService.openWebView` is deliberately not used.
  /// It is declared `void` — it fires a `Navigator.push` and returns immediately
  /// without handing back the route's future — so any caller that starts a timer
  /// or waits for a result after it is timing from the moment the WebView
  /// *opened* rather than the moment it closed. Pushing [PayfastWebView]
  /// directly gives back the real future, so the await ends when the customer
  /// is actually looking at the checkout screen again.
  ///
  /// It also keeps the secured key out of the app entirely: `RedirectionService`
  /// requires `setSecuredKey` and refuses to build without one, so the only way
  /// to use it is to put the real key in the binary.
  static Future<PayfastOutcome?> pay(
    BuildContext context, {
    required String orderId,
    required String customerEmail,
    required String customerMobile,
    required String description,
    void Function(String message)? onError,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      // Only the order id leaves the device. The amount is read from `orders`
      // inside the function; a figure supplied by the app is never trusted.
      final res = await _supabase.functions
          .invoke('payfast-token', body: {'order_id': orderId});
      final d = Map<String, dynamic>.from(res.data as Map);

      // Token error listener equivalent: a 5xx from the gateway comes back as a
      // normal response without a token, which is caught below.
      final token = d['token'] as String?;

      if (token == null || token.isEmpty) {
        onError?.call('Payment is unavailable right now. Please try again.');
        return null;
      }

      if (!context.mounted) return null;

      final result = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (_) => PayfastWebView(
            basketId: d['basket_id'] as String,
            amount: d['amount'] as String,
            description: description,
            customerEmail: customerEmail,
            customerMobile: customerMobile,
            merchantId: d['merchant_id'] as String,
            merchantName: d['merchant_name'] as String,
            token: token,
            successUrl: _successUrl,
            failureUrl: _failureUrl,
            checkoutUrl: _ipnUrl,
            isUAT: _isUat,
            // These fire at the moment the customer reaches the redirect URL.
            // They say nothing about whether the money moved and must never be
            // used to mark an order paid — the IPN is the only thing that does.
            onSuccess: () => messenger.showSnackBar(
                const SnackBar(content: Text('Confirming your payment...'))),
            onFailure: () => messenger.showSnackBar(
                const SnackBar(content: Text('Payment was not completed'))),
          ),
        ),
      );

      final status = result?['status'];
      if (status == 'success') return PayfastOutcome.reachedSuccess;
      if (status == 'failure') return PayfastOutcome.reachedFailure;
      return PayfastOutcome.cancelled;
    } on FunctionException catch (e) {
      onError?.call('Could not start payment (${e.status})');
      return null;
    } catch (e) {
      onError?.call(e.toString());
      return null;
    }
  }

  /// Removes an unpaid online order and every basket row under it.
  ///
  /// The order has to exist before [pay] can run — the gateway reads
  /// `orders.total` for the amount — so a customer who opens PayFast's page and
  /// then backs out has to be taken back to exactly where they were. Returns
  /// false when there was nothing to remove; a refusal (something was paid)
  /// throws and is deliberately not swallowed.
  static Future<bool> discardUnpaidOrder(String orderId) async {
    try {
      final res = await _supabase.rpc(
        'discard_unpaid_order',
        params: {'p_order_id': orderId},
      );
      return res as bool? ?? false;
    } on FunctionException {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  /// Emits the order's payment_status as the IPN function updates it.
  /// Show the success screen only when this emits 'paid'.
  static Stream<String> watchPaymentStatus(String orderId) {
    return _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .where((rows) => rows.isNotEmpty)
        .map((rows) => rows.first['payment_status'] as String);
  }

  /// Waits for `payment_status` to become 'paid', or gives up after [timeout].
  ///
  /// The redirect the customer sees is instant but the IPN is a separate
  /// server-to-server call, so a few seconds of silence is normal and is not
  /// treated as failure. The subscription is always cancelled, including on the
  /// timeout path, or it would outlive the screen watching it.
  static Future<bool> waitForPaid(
    String orderId, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final completer = Completer<bool>();

    final subscription = watchPaymentStatus(orderId).listen((status) {
      if (status == 'paid' && !completer.isCompleted) {
        completer.complete(true);
      }
    });

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });

    final paid = await completer.future;
    timer.cancel();
    await subscription.cancel();
    return paid;
  }
}
