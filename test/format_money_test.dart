import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/utils/money.dart';

void main() {
  group('BUG-6: formatMoney displaying paise when present', () {
    test('reproduce BUG-6: formatMoney shows paise only when non-zero per business rules', () {
      expect(formatMoney(5000), '₹50');
      expect(formatMoney(0), '₹0');
      // In the buggy code, paise is truncated so 4999 paise returns '₹49' instead of '₹49.99'
      expect(formatMoney(4999), '₹49.99',
          reason: 'paise must be shown when non-zero per BUSINESS_RULES.md §1');
      expect(formatMoney(1999), '₹19.99');
      expect(formatMoney(4950), '₹49.50');
    });

    test('reproduce Priority 5: formatMoney correctly formats negative paise values without losing negative sign', () {
      expect(formatMoney(-50), '-₹0.50');
      expect(formatMoney(-100), '-₹1');
      expect(formatMoney(-199), '-₹1.99');
      expect(formatMoney(0), '₹0');
      expect(formatMoney(50), '₹0.50');
      expect(formatMoney(199), '₹1.99');
    });
  });
}
