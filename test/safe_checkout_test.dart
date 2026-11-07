import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/data/config_repository.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  group('Part B: Safe Checkout & Idempotency Integration Tests', () {
    late TestHarness h;

    setUp(() => h = TestHarness());
    tearDown(() => h.dispose());

    test('normal checkout succeeds, creates one order, and empties cart', () async {
      final banana = (await h.read(catalogRepositoryProvider).getPage(categoryId: 'fruits'))
          .items
          .firstWhere((p) => p.id == 'fruits-01');

      await h.read(cartControllerProvider.notifier).add(banana);

      final result = await h.read(checkoutControllerProvider.notifier).placeOrder();

      expect(result, isA<CheckoutSuccess>());
      expect(h.server.orderCount, 1);
      expect(h.read(cartControllerProvider).isEmpty, isTrue);
    });

    test('lost order response returns existing order on retry without duplicate creation', () async {
      final banana = (await h.read(catalogRepositoryProvider).getPage(categoryId: 'fruits'))
          .items
          .firstWhere((p) => p.id == 'fruits-01');

      await h.read(cartControllerProvider.notifier).add(banana);

      // Tell chaos server to process the order but lose the response
      h.server.chaos.loseNextOrderResponses = 1;

      final checkout = h.read(checkoutControllerProvider.notifier);

      // In placeOrder, timeout triggers automatic retry with the SAME Idempotency-Key
      final result = await checkout.placeOrder();

      // Because the first request succeeded on the server and the retry sent the same key,
      // the server returned the created order (status 200) instead of failing or creating a second one!
      expect(result, isA<CheckoutSuccess>());
      expect(h.server.orderCount, 1,
          reason: 'Exactly one order must exist despite lost response');
      expect(h.read(cartControllerProvider).isEmpty, isTrue);
    });

    test('store closure prevents order placement without hitting server', () async {
      final banana = (await h.read(catalogRepositoryProvider).getPage(categoryId: 'fruits'))
          .items
          .firstWhere((p) => p.id == 'fruits-01');

      await h.read(cartControllerProvider.notifier).add(banana);

      // Simulate store closed via remote config
      h.server.publishConfig({'store_open': false, 'store_closed_message': 'Closed for rain'});
      final config = await h.read(configRepositoryProvider).load();
      h.read(appConfigControllerProvider.notifier).hydrate(config);

      final result = await h.read(checkoutControllerProvider.notifier).placeOrder();

      expect(result, isA<CheckoutFailure>());
      expect((result as CheckoutFailure).message, 'Closed for rain');
      expect(result.canRetry, isFalse);
      expect(h.server.orderCount, 0);
      expect(h.read(cartControllerProvider).isEmpty, isFalse,
          reason: 'Cart must not be cleared on failure');
    });

    test('price increase returns CheckoutNeedsReview and does not create order until accepted', () async {
      final banana = (await h.read(catalogRepositoryProvider).getPage(categoryId: 'fruits'))
          .items
          .firstWhere((p) => p.id == 'fruits-01');

      await h.read(cartControllerProvider.notifier).add(banana);

      // Server increases price
      h.server.setPrice(banana.id, banana.pricePaise + 1000);

      final checkout = h.read(checkoutControllerProvider.notifier);
      final result = await checkout.placeOrder();

      expect(result, isA<CheckoutNeedsReview>(),
          reason: 'User must review and accept price increases');
      expect(h.server.orderCount, 0,
          reason: 'No order must be placed before user accepts changes');

      // Cart controller has been updated to the new price
      final updatedCart = h.read(cartControllerProvider);
      expect(updatedCart.lines.first.unitPricePaise, banana.pricePaise + 1000);

      // Now user accepts changes and places order again
      final secondResult = await checkout.placeOrder();
      expect(secondResult, isA<CheckoutSuccess>());
      expect(h.server.orderCount, 1);
      expect(h.read(cartControllerProvider).isEmpty, isTrue);
    });

    test('silent price drop allows checkout to proceed seamlessly', () async {
      final banana = (await h.read(catalogRepositoryProvider).getPage(categoryId: 'fruits'))
          .items
          .firstWhere((p) => p.id == 'fruits-01');

      await h.read(cartControllerProvider.notifier).add(banana);

      // Server decreases price (price drop)
      h.server.setPrice(banana.id, banana.pricePaise - 500);

      final result = await h.read(checkoutControllerProvider.notifier).placeOrder();

      expect(result, isA<CheckoutSuccess>(),
          reason: 'Price drops can be applied silently per BUSINESS_RULES.md §5');
      expect(h.server.orderCount, 1);
    });

    test('offline checkout fails honestly with NetworkException message', () async {
      final banana = (await h.read(catalogRepositoryProvider).getPage(categoryId: 'fruits'))
          .items
          .firstWhere((p) => p.id == 'fruits-01');

      await h.read(cartControllerProvider.notifier).add(banana);

      h.server.chaos.offline = true;

      final result = await h.read(checkoutControllerProvider.notifier).placeOrder();

      expect(result, isA<CheckoutFailure>());
      expect((result as CheckoutFailure).message, contains('offline'));
      expect(result.canRetry, isTrue);
      expect(h.server.orderCount, 0);
      expect(h.read(cartControllerProvider).isEmpty, isFalse);
    });
  });
}
