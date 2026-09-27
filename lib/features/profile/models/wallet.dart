/// One movement of money in the wallet.
///
/// The amount is stored as a real number and the kind carries the direction, so
/// the balance can be derived by summing. The previous screen stored
/// pre-formatted strings like '+ Rs. 0.00', which is why tapping a button could
/// add money but nothing could ever be taken out or reconciled.
enum WalletTransactionKind {
  /// Money arriving: a top up, or a refund.
  credit,

  /// Money leaving: paying for an order.
  debit,
}

/// A single ledger entry.
class WalletTransaction {
  /// A positive number. The direction comes from [kind], not the sign, so a
  /// formatting bug can never turn a payment into a credit.
  final double amount;

  final WalletTransactionKind kind;
  final String title;
  final String? subtitle;
  final DateTime occurredAt;

  const WalletTransaction({
    required this.amount,
    required this.kind,
    required this.title,
    this.subtitle,
    required this.occurredAt,
  });

  /// Signed value, which is what gets summed into the balance.
  double get signedAmount =>
      kind == WalletTransactionKind.credit ? amount : -amount;

  /// What the movement is worth with a sign, e.g. "+500.00" or "-1,250.00".
  String get signedLabel {
    final sign = kind == WalletTransactionKind.credit ? '+' : '-';
    return '$sign${formatRupees(amount)}';
  }

  bool get isCredit => kind == WalletTransactionKind.credit;
}

/// Formats a rupee amount the way a statement does: thousands separated, always
/// two decimals, so a column of them lines up.
String formatRupees(double amount) {
  final fixed = amount.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final digits = parts.first;
  final buffer = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    buffer.write(digits[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buffer.write(',');
  }
  return '${buffer.toString()}.${parts.last}';
}

/// Formats a timestamp as "26 Sep, 8:42 PM".
String formatWalletTimestamp(DateTime when) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final minute = when.minute.toString().padLeft(2, '0');
  final meridiem = when.hour < 12 ? 'AM' : 'PM';
  return '${when.day} ${months[when.month - 1]}, $hour:$minute $meridiem';
}
