/// A policy or help page published on the Mr. Pizza website.
///
/// The website is the one place these documents are written and kept current.
/// Copying their text into Dart would give the app a second version that drifts
/// the moment the restaurant edits a refund term, and a customer could then be
/// shown wording the business no longer stands behind. So the app carries only
/// the label and the address, and always renders the live page.
///
/// The paths are the ones the site actually serves; [siteBaseUrl] is the only
/// place the host is written down.
enum SupportDocument {
  termsAndConditions(
    label: 'Terms & Conditions',
    path: '/terms-and-conditions',
  ),
  privacyPolicy(
    label: 'Privacy Policy',
    path: '/privacy-policy',
  ),
  returnPolicy(
    label: 'Return Policy',
    path: '/return-policy',
  ),
  refundPolicy(
    label: 'Refund Policy',
    path: '/refund-policy',
  ),
  faqs(
    label: 'FAQs',
    path: '/faqs',
  );

  const SupportDocument({required this.label, required this.path});

  /// What the customer sees in the Support Center list and in the page's title.
  final String label;

  /// Path on [siteBaseUrl], kept relative so the host lives in one place.
  final String path;

  /// The public site these documents are published on.
  static const String siteBaseUrl = 'https://www.mrpizzapak.com';

  /// The page itself. HTTPS, so the WebView needs no cleartext exemption.
  Uri get uri => Uri.parse('$siteBaseUrl$path');

  /// The value carried in the route, and the reverse of [fromSlug].
  String get slug => name;

  /// Resolves a document from a route parameter.
  ///
  /// Returns null for anything unrecognised rather than falling back to a
  /// default page. A bad link has to show up as a bad link; quietly opening
  /// some other policy would let the customer read the wrong agreement.
  static SupportDocument? fromSlug(String? slug) {
    if (slug == null || slug.isEmpty) return null;
    for (final document in SupportDocument.values) {
      if (document.slug == slug) return document;
    }
    return null;
  }
}
