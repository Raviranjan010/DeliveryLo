import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  group('BUG-10: Concurrent checkout execution', () {
    late TestHarness h;

    setUp(() => h = TestHarness());
    tearDown(() => h.dispose());

    test('reproduce BUG-10: concurrent placeOrder invocations do not create duplicate orders', () async {
      final banana = (await h.read(catalogRepositoryProvider).getPage(categoryId: 'fruits'))
          .items
          .firstWhere((p) => p.id == 'fruits-01');

      await h.read(cartControllerProvider.notifier).add(banana);

      final checkout = h.read(checkoutControllerProvider.notifier);

      // Simulate double-tap: two concurrent placeOrder calls
      final f1 = checkout.placeOrder();
      final f2 = checkout.placeOrder();

      await Future.wait([f1, f2]);

      // In the buggy code, without concurrent guard and without idempotency key,
      // orderCount would be 2!
      expect(h.server.orderCount, 1,
          reason: 'Double tapping checkout must not produce duplicate orders');
    });
  });
}
