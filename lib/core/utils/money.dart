/// Money helpers.
///
/// Every amount inside the app is an integer number of **paise**
/// (1 rupee = 100 paise). Never store money in a `double`.
library;

/// Formats paise for display.
///
/// Prices are shown in rupees, with paise only when there are any: ₹50, ₹49.99
/// (BUSINESS_RULES.md §1).
String formatMoney(int paise) {
  final isNegative = paise < 0;
  final absPaise = paise.abs();
  final rupees = absPaise ~/ 100;
  final remainder = absPaise % 100;
  final prefix = isNegative ? '-₹' : '₹';

  if (remainder == 0) {
    return '$prefix$rupees';
  }
  return '$prefix$rupees.${remainder.toString().padLeft(2, '0')}';
}

/// Converts a rupee amount coming from the (legacy) API into paise.
int rupeesToPaise(num rupees) => (rupees * 100).round();
