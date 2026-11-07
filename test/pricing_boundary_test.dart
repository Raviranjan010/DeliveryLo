import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';

CartLine _line(String id, int pricePaise, int qty) => CartLine(
      productId: id,
      name: id,
      emoji: '🛒',
      unit: '1 pc',
      unitPricePaise: pricePaise,
      quantity: qty,
      maxPerOrder: 10,
    );

void main() {
  group('BUG-3: Free delivery threshold boundary condition', () {
    final config = AppConfig.defaults(); // threshold ₹199 (19900 paise), fee ₹25 (2500 paise)

    test('reproduce BUG-3: cart of exactly ₹199 (19900 paise) gets free delivery', () {
      final cart = Cart(lines: [_line('item1', 19900, 1)]);
      final pricing = CartPricing.compute(cart, config);

      // In the buggy code, payable > threshold is false when payable == threshold,
      // which wrongly adds 2500 paise delivery fee and causes 409 TOTAL_MISMATCH!
      expect(pricing.deliveryFeePaise, 0,
          reason: 'Orders of ₹199 or more must get free delivery per business rules');
      expect(pricing.totalPaise, 19900);
      expect(pricing.amountForFreeDeliveryPaise, 0);
    });
  });
}
