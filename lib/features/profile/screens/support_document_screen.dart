import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';
import '../models/support_document.dart';

/// Shows one [SupportDocument] exactly as it is published on the website.
///
/// The page is loaded over HTTPS and lives on the business's own domain, so
/// there is no cached copy here to go stale and no second version of the text
/// to keep in step. If the site is unreachable the customer is told so and can
/// retry, or hand the page to the browser, rather than being left on a blank
/// white rectangle.
class SupportDocumentScreen extends StatefulWidget {
  const SupportDocumentScreen({required this.document, super.key});

  final SupportDocument document;

  @override
  State<SupportDocumentScreen> createState() => _SupportDocumentScreenState();
}

class _SupportDocumentScreenState extends State<SupportDocumentScreen> {
  late final WebViewController _controller;

  /// 0-100 as reported by the page. Used for the thin bar under the app bar,
  /// so a slow connection shows movement instead of an apparently frozen page.
  final ValueNotifier<int> _progress = ValueNotifier<int>(0);

  bool _isLoading = true;
  bool _canGoBack = false;

  /// Null while the page is being shown. A non-null value replaces the page with
  /// a readable explanation — an empty WebView with no way forward is the worst
  /// possible outcome for a terms page the customer is being asked to accept.
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            _progress.value = progress;
            if (mounted) {
              final loading = progress < 100;
              if (loading != _isLoading) setState(() => _isLoading = loading);
            }
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });
          },
          onPageFinished: (_) {
            _syncCanGoBack();
          },
          onWebResourceError: (error) {
            // Subresource failures (an image, an analytics ping) must not hide a
            // page that actually rendered. Only a main-frame failure does.
            if (error.isForMainFrame == false) return;
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _errorMessage = error.description.isEmpty
                  ? 'This page could not be loaded.'
                  : error.description;
            });
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            // The policy pages are read inside the app. Anything that is not a
            // web page — a phone number, an email address, a maps link — has to
            // leave for whatever app on the phone handles it, or the WebView
            // would sit on an unsupported scheme doing nothing.
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return NavigationDecision.navigate;
            }
            _openExternally(uri);
            return NavigationDecision.prevent;
          },
        ),
      );

    _controller.loadRequest(widget.document.uri);
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  /// Re-runs the request after a failure. Kept separate from the initial load so
  /// the first request happens without a needless state change during initState.
  void _loadDocument() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _controller.loadRequest(widget.document.uri);
  }

  /// Keeps [_canGoBack] honest, so the system back button follows the page's
  /// own history before it leaves the screen. Without this, pressing back after
  /// following a link inside the page would close the whole policy view.
  Future<void> _syncCanGoBack() async {
    final canGoBack = await _controller.canGoBack();
    if (!mounted) return;
    if (canGoBack == _canGoBack && !_isLoading) return;
    setState(() {
      _canGoBack = canGoBack;
      _isLoading = false;
    });
  }

  Future<void> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      await _syncCanGoBack();
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _openExternally(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No app is installed to open that link.')),
      );
    }
  }

  Future<void> _openInBrowser() async {
    final opened = await launchUrl(
      widget.document.uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No browser is installed on this phone.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(widget.document.label),
          backgroundColor: AppColors.surface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: _handleBack,
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Always mounted, never conditionally removed: tearing the platform
            // view down and rebuilding it on every retry is avoidable churn.
            WebViewWidget(controller: _controller),
            if (_isLoading)
              Align(
                alignment: Alignment.topCenter,
                child: ValueListenableBuilder<int>(
                  valueListenable: _progress,
                  builder: (context, progress, _) => LinearProgressIndicator(
                    minHeight: 2,
                    value: progress > 0 ? progress / 100 : null,
                    backgroundColor: AppColors.border,
                    color: AppColors.primary,
                  ),
                ),
              ),
            if (_errorMessage != null) _buildErrorOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MrIconWell(
                icon: Icons.wifi_off_rounded,
                size: 28,
                color: AppColors.warning,
                background: AppColors.goldTint,
              ),
              const SizedBox(height: 18),
              Text(
                'We could not load ${widget.document.label}.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Check your internet connection and try again.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loadDocument,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open in browser'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
