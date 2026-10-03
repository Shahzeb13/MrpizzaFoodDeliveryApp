/// Loyalty points as the database reports them.
///
/// Nothing here is invented: the balance is the sum of a ledger the app cannot
/// write to, the earn rate is whatever the admin last set, and every entry type
/// that now really occurs is modelled rather than collapsed into "added" and
/// "removed".
library;

/// What a ledger row was for.
///
/// All three occur in practice. `reversed` is not a fourth kind of earning — it
/// is points coming back when an order is cancelled, and it must never be drawn
/// like a reward.
enum LoyaltyEntryType {
  earned,
  redeemed,
  reversed,
}

/// Reads the database's `entry_type`.
///
/// Unknown values map to null so an entry written by a newer server is shown
/// with its real reason rather than mislabelled as something it is not.
LoyaltyEntryType? loyaltyEntryTypeFromDatabase(String? value) {
  switch (value) {
    case 'earned':
      return LoyaltyEntryType.earned;
    case 'redeemed':
      return LoyaltyEntryType.redeemed;
    case 'reversed':
      return LoyaltyEntryType.reversed;
    default:
      return null;
  }
}

/// One row of `loyalty_ledger`, as returned inside `get_my_loyalty_balance()`.
class LoyaltyEntry {
  /// Signed. Negative means spent or clawed back — the sign is the only thing
  /// that makes a deduction look like a deduction.
  final int points;
  final LoyaltyEntryType? type;
  final String reason;
  final DateTime? createdAt;

  /// The order this entry belongs to, when it belongs to one.
  final String? orderId;

  const LoyaltyEntry({
    required this.points,
    required this.type,
    required this.reason,
    required this.createdAt,
    required this.orderId,
  });

  /// True when points left the balance. `reversed` is excluded: money coming
  /// back is not a spend.
  bool get isDeduction => points < 0;

  /// How the row is worded in the history list. The database's own `reason` is
  /// preferred; the fallback covers a row with no reason text.
  String get title {
    if (reason.trim().isNotEmpty) return reason.trim();
    switch (type) {
      case LoyaltyEntryType.earned:
        return 'Points earned';
      case LoyaltyEntryType.redeemed:
        return 'Points spent';
      case LoyaltyEntryType.reversed:
        return 'Points returned';
      case null:
        return 'Points';
    }
  }

  factory LoyaltyEntry.fromMap(Map<String, dynamic> map) {
    return LoyaltyEntry(
      points: _asInt(map['points']),
      type: loyaltyEntryTypeFromDatabase(map['entry_type']?.toString()),
      reason: _asString(map['reason']),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
      orderId: _asNullableString(map['order_id']),
    );
  }
}

/// The rates the admin has set, read from `store_settings` inside the balance
/// payload.
///
/// Both money fields are `numeric` in Postgres, so they can arrive as an int,
/// a double, or a quoted string. Every screen's wording comes from here — the
/// earn rate is a setting, not a string anyone typed into the app.
class LoyaltySettings {
  /// Whether the shop has switched the feature on. Absent settings read as off,
  /// which is also what the database does: with no settings row there is no
  /// redemption value and `redeem_loyalty_points` refuses.
  final bool enabled;

  /// Rupees that must be spent to earn one point. A divisor: 10 means Rs 10
  /// earns 1 point.
  final double? rupeesPerPoint;

  /// Rupees each point is worth when spent.
  final double? redemptionValue;

  const LoyaltySettings({
    required this.enabled,
    required this.rupeesPerPoint,
    required this.redemptionValue,
  });

  /// The "not configured" case: no settings row, or one with nothing usable in
  /// it. The balance is still real, so this never blanks the balance — it only
  /// withholds rates nobody can read.
  static const unknown = LoyaltySettings(
    enabled: false,
    rupeesPerPoint: null,
    redemptionValue: null,
  );

  bool get hasEarnRate => rupeesPerPoint != null && rupeesPerPoint! > 0;
  bool get hasRedemptionRate => redemptionValue != null && redemptionValue! > 0;

  /// "Earn 1 point for every Rs 10", derived from the configured divisor.
  ///
  /// Null when no rate is configured, so the caller can decide what to say
  /// rather than inventing one. Nothing here assumes Rs 10.
  String? get earnRateLabel {
    if (!hasEarnRate) return null;
    return 'Earn 1 point for every Rs ${_trimAmount(rupeesPerPoint!)}';
  }

  /// "1 point = Rs 1" — what a single point is worth when spent.
  String? get redemptionRateLabel {
    if (!hasRedemptionRate) return null;
    return '1 point = Rs ${_trimAmount(redemptionValue!)}';
  }

  /// What the whole balance is worth in rupees, as a ceiling.
  ///
  /// Only ever shown as "up to". The database clamps a redemption to what the
  /// order can absorb, so this figure is an upper bound and is never presented
  /// as the saving that will actually happen.
  double? get balanceWorthUpperBound {
    if (!hasRedemptionRate) return null;
    return redemptionValue!;
  }

  factory LoyaltySettings.fromMap(Map<String, dynamic> map) {
    final perPoint = _asNullableDouble(map['rupees_per_point']);
    final redemption = _asNullableDouble(map['redemption_value']);

    return LoyaltySettings(
      // The key being absent is what "off" looks like; the database refuses a
      // redemption in exactly that situation, so the two agree.
      enabled: map['enabled'] == true,
      rupeesPerPoint: perPoint,
      redemptionValue: redemption,
    );
  }
}

/// A customer's real points balance, the last 50 ledger rows behind it, and the
/// rates they are worth.
class LoyaltyBalance {
  /// False when the database refused the read because nobody is signed in.
  ///
  /// The refusal's own wording is deliberately not carried here: "Sign in to see
  /// your loyalty points." is a database string, and every screen behind the
  /// router already knows the session state. Surfacing it would tell a signed-in
  /// customer they are signed out whenever a read failed for any other reason.
  final bool isSignedIn;

  final int balance;
  final List<LoyaltyEntry> history;
  final LoyaltySettings settings;

  const LoyaltyBalance({
    required this.isSignedIn,
    required this.balance,
    required this.history,
    required this.settings,
  });

  /// The signed-out read: no balance, no rates, nothing to show.
  static const signedOut = LoyaltyBalance(
    isSignedIn: false,
    balance: 0,
    history: [],
    settings: LoyaltySettings.unknown,
  );

  bool get hasPoints => balance > 0;

  /// Whether it is worth offering the spend control at all: the shop has the
  /// feature on and there is a known rate to convert with.
  bool get canSpendPoints => settings.enabled && settings.hasRedemptionRate;

  /// The newest entry the ledger has for [orderId], if it is inside the
  /// 50-row window.
  ///
  /// Used to show what a specific order earned or spent rather than
  /// recomputing it, so the app can never disagree with the ledger.
  LoyaltyEntry? entryForOrder(String orderId) {
    if (orderId.isEmpty) return null;
    for (final entry in history) {
      if (entry.orderId == orderId) return entry;
    }
    return null;
  }

  /// Points this order earned, from the ledger rather than from the order total.
  ///
  /// Zero when the order is not delivered yet, or when its earning row has
  /// fallen outside the 50-row window — both correctly read as "nothing credited
  /// that this screen can prove".
  int pointsEarnedOnOrder(String orderId) =>
      _netForOrder(orderId, const {LoyaltyEntryType.earned});

  /// Points this order had spent. Shown as a positive number so it can be
  /// labelled with the discount it produced.
  int pointsSpentOnOrder(String orderId) {
    final net = _netForOrder(orderId, const {LoyaltyEntryType.redeemed});
    return net < 0 ? -net : 0;
  }

  /// Sums the signed rows of [orderId] whose type is in [types].
  int _netForOrder(String orderId, Set<LoyaltyEntryType> types) {
    var total = 0;
    for (final entry in history) {
      if (entry.orderId == orderId && types.contains(entry.type)) {
        total += entry.points;
      }
    }
    return total;
  }

  /// Reads the `get_my_loyalty_balance()` payload.
  ///
  /// `ok` is read as a flag, never inferred: a payload missing `ok` is treated
  /// as a refusal, because assuming success is how a balance silently becomes
  /// zero.
  static LoyaltyBalance fromRpcResult(Object? result) {
    final payload = _asMap(result);
    if (payload == null) return signedOut;
    if (payload['ok'] != true) return signedOut;

    final settingsMap = _asMap(payload['settings']);

    return LoyaltyBalance(
      isSignedIn: true,
      balance: _asInt(payload['balance']),
      history: _asList(payload['history']).map(LoyaltyEntry.fromMap).toList(),
      settings: settingsMap == null
          ? LoyaltySettings.unknown
          : LoyaltySettings.fromMap(settingsMap),
    );
  }
}

/// The verdict from `redeem_loyalty_points(p_order_id, p_points)`.
///
/// The money fields are the database's, not a calculation repeated in Dart. A
/// locally computed discount can disagree with the till, so the numbers here
/// replace whatever the app was showing rather than adjusting it.
class LoyaltyRedemption {
  /// False for every refusal the function can return, with the reason.
  final bool ok;
  final String message;

  /// Points actually taken. Can be less than the number asked for: the
  /// database clamps to what the order can absorb and rounds down to whole
  /// points, and this is the clamped figure.
  final int pointsSpent;

  /// Rupees taken off the order.
  final double discountApplied;

  /// The order's total after the discount. Authoritative.
  final double newTotal;

  /// The balance after the spend. The database's own number, which already
  /// accounts for the clamp.
  final int balance;

  const LoyaltyRedemption({
    required this.ok,
    required this.message,
    required this.pointsSpent,
    required this.discountApplied,
    required this.newTotal,
    required this.balance,
  });

  static const failed = LoyaltyRedemption(
    ok: false,
    message: 'We could not spend your points. Please try again.',
    pointsSpent: 0,
    discountApplied: 0,
    newTotal: 0,
    balance: 0,
  );

  /// Reads the `redeem_loyalty_points()` payload.
  ///
  /// A missing `ok` is a refusal, not a success: this function debits a real
  /// ledger, so treating an unreadable answer as a win would tell the customer
  /// they saved money that was never taken off the bill.
  static LoyaltyRedemption fromRpcResult(Object? result) {
    final payload = _asMap(result);
    if (payload == null) return failed;
    if (payload['ok'] != true) {
      return LoyaltyRedemption(
        ok: false,
        message: _asString(payload['message']).isEmpty
            ? failed.message
            : _asString(payload['message']),
        pointsSpent: 0,
        discountApplied: 0,
        newTotal: 0,
        balance: 0,
      );
    }

    return LoyaltyRedemption(
      ok: true,
      message: _asString(payload['message']),
      pointsSpent: _asInt(payload['points_spent']),
      discountApplied: _asDouble(payload['discount_applied']),
      newTotal: _asDouble(payload['new_total']),
      balance: _asInt(payload['balance']),
    );
  }
}

// PostgREST can hand back a bare object or a one-row list, and every numeric
// column in these payloads is `numeric` — a JSON number, or the same digits
// quoted as a string. The readers below tolerate all of it.

Map<String, dynamic>? _asMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List && value.isNotEmpty && value.first is Map) {
    return Map<String, dynamic>.from(value.first as Map);
  }
  return null;
}

List<Map<String, dynamic>> _asList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map(Map<String, dynamic>.from)
      .toList(growable: false);
}

String _asString(Object? value) => value?.toString() ?? '';

String? _asNullableString(Object? value) {
  final text = _asString(value).trim();
  return text.isEmpty ? null : text;
}

int _asInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim()) ?? 0;
  return 0;
}

/// Double that keeps a whole number whole and trims a fractional one's trailing
/// zeros, so a rate reads "10" and "7.50" reads "7.5".
double? _asNullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }
  return null;
}

String _trimAmount(double amount) {
  if (amount == amount.roundToDouble()) return amount.toInt().toString();
  return amount
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}