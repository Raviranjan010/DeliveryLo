import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/utils/money.dart';

void main() {
  group('BUG-5: Floating point precision in rupeesToPaise', () {
    test('reproduce BUG-5: 49.99 rupees converts to 4999 paise without off-by-one truncation', () {
      // In the buggy code: (49.99 * 100).toInt() produces 4998 because
      // IEEE-754 representation of 49.99 * 100 is 4998.999999999999.
      expect(rupeesToPaise(49.99), 4999,
          reason: '49.99 rupees must equal 4999 paise');
      expect(rupeesToPaise(19.99), 1999,
          reason: '19.99 rupees must equal 1999 paise');
      expect(rupeesToPaise(79.99), 7999,
          reason: '79.99 rupees must equal 7999 paise');
      expect(rupeesToPaise(69.99), 6999,
          reason: '69.99 rupees must equal 6999 paise');
      expect(rupeesToPaise(17.99), 1799,
          reason: '17.99 rupees must equal 1799 paise');
    });
  });
}
