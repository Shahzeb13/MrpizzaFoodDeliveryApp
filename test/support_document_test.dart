import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/profile/models/support_document.dart';

void main() {
  group('the documents the Support Center offers', () {
    test('is the full set the business publishes', () {
      expect(
        SupportDocument.values.map((document) => document.label),
        [
          'Terms & Conditions',
          'Privacy Policy',
          'Return Policy',
          'Refund Policy',
          'FAQs',
        ],
      );
    });

    test('every page is an HTTPS page on the Mr. Pizza site', () {
      for (final document in SupportDocument.values) {
        expect(document.uri.scheme, 'https',
            reason: '${document.label} must not need a cleartext exemption');
        expect(document.uri.host, 'www.mrpizzapak.com');
        expect(document.uri.path, document.path);
      }
    });

    test('every path is distinct, so two entries cannot open one page', () {
      final paths = SupportDocument.values.map((document) => document.path);
      expect(paths.toSet(), hasLength(SupportDocument.values.length));
    });
  });

  group('reading a document back from its route value', () {
    test('round trips every document through its slug', () {
      for (final document in SupportDocument.values) {
        expect(SupportDocument.fromSlug(document.slug), document);
      }
    });

    test('a missing or unknown slug is null, never a default page', () {
      // A wrong link has to be visibly wrong. Falling back to, say, the terms
      // page would let a customer read an agreement they did not open.
      expect(SupportDocument.fromSlug(null), isNull);
      expect(SupportDocument.fromSlug(''), isNull);
      expect(SupportDocument.fromSlug('not-a-document'), isNull);
      expect(SupportDocument.fromSlug('/terms-and-conditions'), isNull);
    });
  });
}
