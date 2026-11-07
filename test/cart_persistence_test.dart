import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/cart/data/cart_storage.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';

import 'helpers/test_harness.dart';

void main() {
  group('QK-101: Cart persistence on mutations', () {
    late TestHarness h;

    setUp(() => h = TestHarness());
    tearDown(() => h.dispose());

    test('reproduce QK-101: decrement, remove, and removeCoupon persist across restart', () async {
      final banana = h.server.product('fruits-01');
      final apple = h.server.product('fruits-00');

      final cartController = h.read(cartControllerProvider.notifier);

      // Add 2 bananas and 1 apple
      final pBanana = (await h.read(catalogRepositoryProvider).getPage(categoryId: 'fruits'))
          .items
          .firstWhere((p) => p.id == banana.id);
      final pApple = (await h.read(catalogRepositoryProvider).getPage(categoryId: 'fruits'))
          .items
          .firstWhere((p) => p.id == apple.id);

      await cartController.add(pBanana);
      await cartController.add(pBanana);
      await cartController.add(pApple);

      final coupon = Coupon(
        code: 'SAVE10',
        type: CouponType.percent,
        value: 10,
        minOrderPaise: 1000,
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      await cartController.applyCoupon(coupon);

      expect(h.read(cartControllerProvider).quantityOf(banana.id), 2);
      expect(h.read(cartControllerProvider).quantityOf(apple.id), 1);
      expect(h.read(cartControllerProvider).coupon, isNotNull);

      // Now decrement banana to 1, remove apple, and remove coupon
      await cartController.decrement(banana.id);
      await cartController.remove(apple.id);
      await cartController.removeCoupon();

      expect(h.read(cartControllerProvider).quantityOf(banana.id), 1);
      expect(h.read(cartControllerProvider).quantityOf(apple.id), 0);
      expect(h.read(cartControllerProvider).coupon, isNull);

      // Simulate app restart: load cart from storage
      final h2 = h.restart();
      final restoredCart = await h2.read(cartStorageProvider).load();
      h2.dispose();

      // In the buggy code, storage still has 2 bananas, 1 apple, and the coupon!
      expect(restoredCart.quantityOf(banana.id), 1,
          reason: 'Decremented quantity must persist to storage');
      expect(restoredCart.lineFor(apple.id), isNull,
          reason: 'Removed item must not return after restart');
      expect(restoredCart.coupon, isNull,
          reason: 'Removed coupon must not return after restart');
    });
  });
}
