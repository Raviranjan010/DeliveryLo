import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/network/api_exceptions.dart';
import 'package:quickkart/features/cart/application/cart_reconciler.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/coupon.dart';
import 'package:quickkart/features/cart/domain/reconciliation.dart';

import 'helpers/test_harness.dart';

void main() {
  group('CartReconciler.reconcile contract tests', () {
    late TestHarness h;
    late CartReconciler reconciler;

    setUp(() {
      h = TestHarness();
      reconciler = h.read(cartReconcilerProvider);
    });

    tearDown(() => h.dispose());

    test('empty cart reconciles to empty cart with no changes', () async {
      final result = await reconciler.reconcile(const Cart.empty());
      expect(result.cart.isEmpty, isTrue);
      expect(result.changes, isEmpty);
      expect(result.requiresUserReview, isFalse);
    });

    test('unchanged cart reconciles to equal cart with no changes', () async {
      final banana = h.server.product('fruits-01');
      final cart = Cart(lines: [
        CartLine(
          productId: banana.id,
          name: banana.name,
          emoji: '🍌',
          unit: '6 pcs',
          unitPricePaise: banana.pricePaise,
          quantity: 2,
          maxPerOrder: banana.maxPerOrder,
        ),
      ]);

      final result = await reconciler.reconcile(cart);
      expect(result.cart, equals(cart));
      expect(result.changes, isEmpty);
      expect(result.requiresUserReview, isFalse);
    });

    test('price increase triggers PriceChanged and requires user review', () async {
      final banana = h.server.product('fruits-01');
      final oldPrice = banana.pricePaise;
      final newPrice = oldPrice + 1000;
      h.server.setPrice(banana.id, newPrice);

      final cart = Cart(lines: [
        CartLine(
          productId: banana.id,
          name: banana.name,
          emoji: '🍌',
          unit: '6 pcs',
          unitPricePaise: oldPrice,
          quantity: 2,
          maxPerOrder: banana.maxPerOrder,
        ),
      ]);

      final result = await reconciler.reconcile(cart);
      expect(result.cart.lines.first.unitPricePaise, newPrice);
      expect(result.changes.length, 1);
      final change = result.changes.first;
      expect(change, isA<PriceChanged>());
      expect((change as PriceChanged).isIncrease, isTrue);
      expect(change.requiresUserReview, isTrue);
      expect(result.requiresUserReview, isTrue);
    });

    test('price decrease triggers PriceChanged but does NOT require user review', () async {
      final banana = h.server.product('fruits-01');
      final oldPrice = banana.pricePaise;
      final newPrice = oldPrice - 500;
      h.server.setPrice(banana.id, newPrice);

      final cart = Cart(lines: [
        CartLine(
          productId: banana.id,
          name: banana.name,
          emoji: '🍌',
          unit: '6 pcs',
          unitPricePaise: oldPrice,
          quantity: 2,
          maxPerOrder: banana.maxPerOrder,
        ),
      ]);

      final result = await reconciler.reconcile(cart);
      expect(result.cart.lines.first.unitPricePaise, newPrice);
      expect(result.changes.length, 1);
      final change = result.changes.first;
      expect(change, isA<PriceChanged>());
      expect((change as PriceChanged).isIncrease, isFalse);
      expect(change.requiresUserReview, isFalse);
      expect(result.requiresUserReview, isFalse);
    });

    test('out of stock product triggers OutOfStock and is removed from cart', () async {
      final banana = h.server.product('fruits-01');
      h.server.setStock(banana.id, 0);

      final cart = Cart(lines: [
        CartLine(
          productId: banana.id,
          name: banana.name,
          emoji: '🍌',
          unit: '6 pcs',
          unitPricePaise: banana.pricePaise,
          quantity: 2,
          maxPerOrder: banana.maxPerOrder,
        ),
      ]);

      final result = await reconciler.reconcile(cart);
      expect(result.cart.lines, isEmpty);
      expect(result.changes.length, 1);
      expect(result.changes.first, isA<OutOfStock>());
      expect(result.requiresUserReview, isTrue);
    });

    test('reduced stock clamps quantity and triggers QuantityReduced', () async {
      final banana = h.server.product('fruits-01');
      h.server.setStock(banana.id, 2);

      final cart = Cart(lines: [
        CartLine(
          productId: banana.id,
          name: banana.name,
          emoji: '🍌',
          unit: '6 pcs',
          unitPricePaise: banana.pricePaise,
          quantity: 5,
          maxPerOrder: 6,
        ),
      ]);

      final result = await reconciler.reconcile(cart);
      expect(result.cart.lines.first.quantity, 2);
      expect(result.cart.lines.first.maxPerOrder, 2);
      expect(result.changes.length, 1);
      final change = result.changes.first as QuantityReduced;
      expect(change.requestedQuantity, 5);
      expect(change.availableQuantity, 2);
      expect(result.requiresUserReview, isTrue);
    });

    test('discontinued/missing product triggers ProductUnavailable and is removed', () async {
      final banana = h.server.product('fruits-01');
      h.server.setActive(banana.id, false);

      final cart = Cart(lines: [
        CartLine(
          productId: banana.id,
          name: banana.name,
          emoji: '🍌',
          unit: '6 pcs',
          unitPricePaise: banana.pricePaise,
          quantity: 1,
          maxPerOrder: 4,
        ),
      ]);

      final result = await reconciler.reconcile(cart);
      expect(result.cart.lines, isEmpty);
      expect(result.changes.length, 1);
      expect(result.changes.first, isA<ProductUnavailable>());
      expect(result.requiresUserReview, isTrue);
    });

    test('expired coupon triggers CouponRemoved and is removed from cart', () async {
      h.server.expireCoupon('SAVE10');

      final coupon = Coupon(
        code: 'SAVE10',
        type: CouponType.percent,
        value: 10,
        minOrderPaise: 19900,
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      final cart = Cart(lines: const [], coupon: coupon);

      final result = await reconciler.reconcile(cart);
      expect(result.cart.coupon, isNull);
      expect(result.changes.length, 1);
      final change = result.changes.first as CouponRemoved;
      expect(change.code, 'SAVE10');
      expect(change.reason, 'EXPIRED');
      expect(result.requiresUserReview, isTrue);
    });

    test('product with both price drift and zero stock emits only OutOfStock event', () async {
      final banana = h.server.product('fruits-01');
      final oldPrice = banana.pricePaise;
      final newPrice = oldPrice + 500;
      h.server.setPrice(banana.id, newPrice);
      h.server.setStock(banana.id, 0);

      final cart = Cart(lines: [
        CartLine(
          productId: banana.id,
          name: banana.name,
          emoji: '🍌',
          unit: '6 pcs',
          unitPricePaise: oldPrice,
          quantity: 2,
          maxPerOrder: banana.maxPerOrder,
        ),
      ]);

      final result = await reconciler.reconcile(cart);
      expect(result.cart.lines, isEmpty);
      // Ensure contradictory PriceChanged is not emitted for unavailable product
      expect(result.changes.length, 1);
      expect(result.changes.first, isA<OutOfStock>());
      expect((result.changes.first as OutOfStock).productId, banana.id);
      expect(result.requiresUserReview, isTrue);
    });

    test('network failure rethrows ApiException without returning partial cart', () async {
      h.server.chaos.offline = true;

      final banana = h.server.product('fruits-01');
      final cart = Cart(lines: [
        CartLine(
          productId: banana.id,
          name: banana.name,
          emoji: '🍌',
          unit: '6 pcs',
          unitPricePaise: banana.pricePaise,
          quantity: 1,
          maxPerOrder: 4,
        ),
      ]);

      await expectLater(
        reconciler.reconcile(cart),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
