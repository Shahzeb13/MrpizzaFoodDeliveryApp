import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PayfastWebView extends StatefulWidget {
  final String basketId;
  final String amount;
  final String description;
  final String customerEmail;
  final String customerMobile;
  final String merchantId;
  final String merchantName;
  final String token;
  final String successUrl;
  final VoidCallback? onSuccess;
  final String failureUrl;
  final VoidCallback? onFailure;
  final String checkoutUrl;
  final bool isUAT;

  const PayfastWebView({
    super.key,
    required this.basketId,
    required this.amount,
    required this.description,
    required this.customerEmail,
    required this.customerMobile,
    required this.merchantId,
    required this.merchantName,
    required this.token,
    required this.successUrl,
    this.onSuccess,
    required this.failureUrl,
    this.onFailure,
    required this.checkoutUrl,
    required this.isUAT,
  });

  @override
  State<PayfastWebView> createState() => _PayfastWebViewState();
}

class _PayfastWebViewState extends State<PayfastWebView> {
  late final WebViewController _controller;

  /// A ValueNotifier rather than plain state + setState.
  ///
  /// The navigation callbacks below fire while the customer is typing — the
  /// gateway's card field validates as digits arrive, which can restart the
  /// page. Every setState from here rebuilt the whole Stack, and a rebuilt
  /// platform view drops its IME connection: the field being typed in lost focus
  /// after a single keystroke. Notifying a ValueNotifier rebuilds only the
  /// spinner, leaving the WebView's element and its Android view untouched.
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(true);

  @override
  void dispose() {
    _isLoading.dispose();
    super.dispose();
  }

  String get _postUrl => widget.isUAT
      ? 'https://ipguat.apps.net.pk/Ecommerce/api/Transaction/PostTransaction'
      : 'https://ipg1.apps.net.pk/Ecommerce/api/Transaction/PostTransaction';

  String _getOrderDate() {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  String _buildPaymentParams() {
    final orderDate = _getOrderDate();
    return 'TOKEN=${Uri.encodeComponent(widget.token)}'
        '&MERCHANT_ID=${Uri.encodeComponent(widget.merchantId)}'
        '&MERCHANT_NAME=${Uri.encodeComponent(widget.merchantName)}'
        '&PROCCODE=00'
        '&TXNAMT=${Uri.encodeComponent(widget.amount)}'
        '&CUSTOMER_MOBILE_NO=${Uri.encodeComponent(widget.customerMobile)}'
        '&CUSTOMER_EMAIL_ADDRESS=${Uri.encodeComponent(widget.customerEmail)}'
        '&SIGNATURE=testsign'
        '&VERSION=MERCHANT-CART-0.1'
        '&TXNDESC=${Uri.encodeComponent(widget.description)}'
        '&SUCCESS_URL=${Uri.encodeComponent(widget.successUrl)}'
        '&FAILURE_URL=${Uri.encodeComponent(widget.failureUrl)}'
        '&BASKET_ID=${Uri.encodeComponent(widget.basketId)}'
        '&ORDER_DATE=${Uri.encodeComponent(orderDate)}'
        '&CHECKOUT_URL=${Uri.encodeComponent(widget.checkoutUrl)}'
        '&CURRENCY_CODE=PKR'
        '&TRAN_TYPE=ECOMM_PURCHASE'
        '&STORE_ID='
        '&BILL_NUMBER='
        '&CUSTOMER_ID='
        '&ADDITIONAL_VALUE=${Uri.encodeComponent(orderDate)}'
        '&RECURRING_TXN=';
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            _isLoading.value = true;
          },
          onPageFinished: (String url) {
            _isLoading.value = false;
            if (url.contains(widget.successUrl)) {
              _handleSuccess();
            } else if (url.contains(widget.failureUrl)) {
              _handleFailure();
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url;
            if (url.contains(widget.successUrl) ||
                url.startsWith(widget.successUrl)) {
              _handleSuccess();
              return NavigationDecision.prevent;
            }
            if (url.contains(widget.failureUrl) ||
                url.startsWith(widget.failureUrl)) {
              _handleFailure();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    _controller.loadRequest(
      Uri.parse(_postUrl),
      method: LoadRequestMethod.post,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: utf8.encode(_buildPaymentParams()),
    );
  }

  void _handleSuccess() {
    widget.onSuccess?.call();
    if (mounted) {
      Navigator.pop(context, {'status': 'success'});
    }
  }

  void _handleFailure() {
    widget.onFailure?.call();
    if (mounted) {
      Navigator.pop(context, {'status': 'failure'});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payfast Payment'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // First child, always present, never wrapped in anything that changes
          // identity — see the note on [_isLoading].
          WebViewWidget(controller: _controller),
          ValueListenableBuilder<bool>(
            valueListenable: _isLoading,
            builder: (context, loading, _) => loading
                ? const Center(child: CircularProgressIndicator())
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
