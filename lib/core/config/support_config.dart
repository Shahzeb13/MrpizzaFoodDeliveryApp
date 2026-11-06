import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

/// Every way a customer can reach the restaurant, in one place.
///
/// The Support screen, the email prefills and the copy fallbacks all read
/// from here, so a number or an address change is one edit in one file and
/// nowhere else. Nothing in here is invented: every number, link and address
/// below is the branch's own published contact detail.
class SupportBranch {
  const SupportBranch({
    required this.name,
    required this.phones,
    required this.whatsappUrl,
    required this.address,
  });

  /// Shown as the branch card's heading.
  final String name;

  /// Phone numbers as the customer reads them, dialled via `tel:`.
  final List<String> phones;

  /// The `https://wa.me/` link, numbers in international format with no
  /// leading zero, so it works worldwide regardless of the phone's locale.
  final String whatsappUrl;

  /// Where the branch is, as printed on the website.
  final String address;

  /// Dial addresses for [phones]: `tel:` keeps only the digits, so
  /// "0992-414178" becomes 0992414178 and dials correctly everywhere.
  List<Uri> get dialUris => phones
      .map((phone) => Uri(scheme: 'tel', path: digitsOnly(phone)))
      .toList(growable: false);

  static String digitsOnly(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9]'), '');
}

/// The shared support inbox. One email for both branches.
const String supportEmailAddress = 'mrpizzapak@gmail.com';

/// The branches, in the order the Support screen lists them.
final List<SupportBranch> supportBranches = [
  supportAbbottabadBranch,
  supportMansehraBranch,
];

const SupportBranch supportAbbottabadBranch = SupportBranch(
  name: 'Abbottabad Branch',
  phones: ['0992-414178', '0300-5003494'],
  whatsappUrl: 'https://wa.me/923005003494',
  address: 'Mr Plaza, Opp AMC, Mandian, Abbottabad',
);

const SupportBranch supportMansehraBranch = SupportBranch(
  name: 'Mansehra Branch',
  phones: ['0997-391645', '0997-391630'],
  whatsappUrl: 'https://wa.me/923000391645',
  address: 'K.K Plaza, near Saadi CNG, Upper Channai, Abbottabad Road, Mansehra',
);

// TODO: confirm hours with owner
const String supportHoursText =
    'Support hours: every day, 8:00 AM to 4:00 AM (Pakistan time). Phone and '
    'WhatsApp answer during these hours; email replies within 24 hours.';

const String supportWebsiteUrl = 'https://www.mrpizzapak.com';

/// The email the Support screen composes.
///
/// The subject carries the order bill number when the customer came from
/// "Problem with this order?", so the inbox threads every message about one
/// order. The body always carries the app version and platform so support can
/// reproduce on the exact build. This never includes anything private — no
/// cart contents, session tokens or account details ride along.
Uri supportEmailUri({String? orderReference}) => Uri(
      scheme: 'mailto',
      path: supportEmailAddress,
      queryParameters: {
        'subject': (orderReference == null || orderReference.isEmpty)
            ? 'MrPizza support'
            : 'MrPizza support - Order #$orderReference',
        'body': 'Hello Mr. Pizza team,\n\n'
            'Order: ${orderReference?.isEmpty ?? true ? '-' : orderReference}\n'
            'My issue:',
      },
    );

/// The same [supportEmailUri] prefill, with version and platform filled in
/// from the running build. Async because the package info is read per call.
Future<Uri> buildSupportEmailUri({String? orderReference}) async {
  final info = await PackageInfo.fromPlatform();
  final platform = Platform.isIOS
      ? 'iOS'
      : Platform.isAndroid
          ? 'Android'
          : Platform.operatingSystem;

  final base = supportEmailUri(orderReference: orderReference);
  final query = base.queryParameters;
  return base.replace(queryParameters: {
    ...query,
    'body': '${query['body']!}\n'
        'App version: ${info.version} (${info.buildNumber})\n'
        'Platform: $platform\n',
  });
}
