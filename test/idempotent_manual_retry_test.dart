import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/cart/application/cart_controller.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/checkout/application/checkout_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  group('Priority 1: Lost response and manual retry idempotency recovery', () {
    late TestHarness h;

    setUp(() => h = TestHarness());
    tearDown(() => h.dispose());

    test('reproduce Priority 1: manual retry of lost response recovers existing order even when stock is now 0', () async {
      // 1. Stock begins at 1
      final banana = (await h.read(catalogRepositoryProvider).getPage(categoryId: 'fruits'))
          .items
          .firstWhere((p) => p.id == 'fruits-01');
      h.server.setStock(banana.id, 1);

      // Customer orders 1 unit
      await h.read(cartControllerProvider.notifier).add(banana);
      expect(h.read(cartControllerProvider).quantityOf(banana.id), 1);

      // 2. Server processes the order but 2 responses are lost (initial + automatic retry)
      h.server.chaos.loseNextOrderResponses = 2;

      final checkout = h.read(checkoutControllerProvider.notifier);

      // Initial checkout call: times out and exhausts automatic retry
      final firstResult = await checkout.placeOrder();
      expect(firstResult, isA<CheckoutFailure>());
      expect((firstResult as CheckoutFailure).canRetry, isTrue);

      // Verify that the server DID process the order on the first attempt
      expect(h.server.orderCount, 1,
          reason: 'Server processed the order before response was lost');
      // Server inventory was decremented to 0
      expect(h.server.product(banana.id).stock, 0);

      // 3. Customer manually retries by tapping "Place order" again
      // In the defective implementation:
      // placeOrder() runs pre-checkout reconcile(cart). reconcile sees server stock is 0,
      // classifies it as OutOfStock, resets the idempotency key, and returns CheckoutNeedsReview!
      // The order created on the server is orphaned and never recovered!
      final retryResult = await checkout.placeOrder();

      expect(retryResult, isA<CheckoutSuccess>(),
          reason: 'Manual retry must recover the existing order using the original key and payload');

      // Exactly ONE server order must exist (no duplicates)
      expect(h.server.orderCount, 1,
          reason: 'Exactly one order must exist on the server');

      // Cart is cleared only after confirmed success
      expect(h.read(cartControllerProvider).isEmpty, isTrue,
          reason: 'Cart must be cleared after confirmed CheckoutSuccess');
    });

    test('when request was never processed and stock genuinely changed, 409 triggers reconciliation', () async {
      final banana = (await h.read(catalogRepositoryProvider).getPage(categoryId: 'fruits'))
          .items
          .firstWhere((p) => p.id == 'fruits-01');
      h.server.setStock(banana.id, 2);

      await h.read(cartControllerProvider.notifier).add(banana);

      // Request fails before server processing (e.g. offline)
      h.server.chaos.offline = true;

      final checkout = h.read(checkoutControllerProvider.notifier);
      final offlineResult = await checkout.placeOrder();
      expect(offlineResult, isA<CheckoutFailure>());
      expect(h.server.orderCount, 0);

      // Back online, but another customer bought the stock on the server
      h.server.chaos.offline = false;
      h.server.setStock(banana.id, 0);

      // Retry: server returns 409 INSUFFICIENT_STOCK, which triggers reconciliation
      final retryResult = await checkout.placeOrder();
      expect(retryResult, isA<CheckoutNeedsReview>(),
          reason: 'Unprocessed order with depleted stock must trigger review');
      expect(h.server.orderCount, 0);
    });
  });
}
