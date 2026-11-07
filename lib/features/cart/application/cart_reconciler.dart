import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/data/catalog_api.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/domain/product.dart';
import '../../../core/network/api_exceptions.dart';
import '../data/coupon_api.dart';
import '../domain/cart.dart';
import '../domain/coupon.dart';
import '../domain/reconciliation.dart';

final cartReconcilerProvider = Provider<CartReconciler>(
  (ref) => CartReconciler(
    catalogApi: ref.watch(catalogApiProvider),
    couponApi: ref.watch(couponApiProvider),
  ),
);

/// Compares a local cart with the server's current state.
class CartReconciler {
  CartReconciler({required this.catalogApi, required this.couponApi});

  final CatalogApi catalogApi;
  final CouponApi couponApi;

  /// Contract (checked by hidden tests - see ASSIGNMENT.md, Feature 1):
  ///
  /// Returns a [ReconciliationResult] whose `cart` is what could be ordered
  /// right now:
  /// * every line's `unitPricePaise` equals the server's current price;
  /// * every line's `quantity` is `<= min(stock, maxPerOrder)` and its
  ///   `maxPerOrder` is refreshed to that same value;
  /// * lines whose product is out of stock or no longer sold are removed;
  /// * the coupon is removed if it is expired or unknown, otherwise it is
  ///   refreshed with the server's latest rules (a coupon whose minimum
  ///   order is not met stays in the cart - see BUSINESS_RULES.md);
  /// * the order of the remaining lines is preserved.
  ///
  /// `changes` lists every difference (one [CartChange] per product/coupon
  /// issue). An unchanged cart returns an empty list and an equal cart.
  ///
  /// Throws an `ApiException` if the server cannot be reached. It must never
  /// return a partially reconciled cart.
  Future<ReconciliationResult> reconcile(Cart cart) async {
    if (cart.isEmpty && cart.coupon == null) {
      return ReconciliationResult(cart: cart, changes: const []);
    }

    final changes = <CartChange>[];
    final reconciledLines = <CartLine>[];

    // 1. Reconcile products if cart has any lines
    if (cart.lines.isNotEmpty) {
      final allProductIds = cart.lines.map((l) => l.productId).toList();

      // Chunk in batches of 50 as per API contract
      final returnedProducts = <Product>[];
      final missingIds = <String>{};

      for (var i = 0; i < allProductIds.length; i += 50) {
        final chunk = allProductIds.sublist(i, min(i + 50, allProductIds.length));
        final batch = await catalogApi.getProductsByIds(chunk);
        returnedProducts.addAll(batch.products);
        missingIds.addAll(batch.missingIds);
      }

      final productMap = {for (final p in returnedProducts) p.id: p};

      // Preserve original line ordering
      for (final line in cart.lines) {
        if (missingIds.contains(line.productId) || !productMap.containsKey(line.productId)) {
          changes.add(ProductUnavailable(productId: line.productId));
          continue; // Omitted from reconciled cart
        }

        final serverProduct = productMap[line.productId]!;

        // Price drift check
        if (line.unitPricePaise != serverProduct.pricePaise) {
          changes.add(PriceChanged(
            productId: line.productId,
            oldPricePaise: line.unitPricePaise,
            newPricePaise: serverProduct.pricePaise,
          ));
        }

        // Availability and stock limit checks
        if (serverProduct.stock <= 0) {
          changes.add(OutOfStock(productId: line.productId));
          continue; // Omitted from reconciled cart
        }

        final availableLimit = min(serverProduct.stock, serverProduct.maxPerOrder);
        if (line.quantity > availableLimit) {
          changes.add(QuantityReduced(
            productId: line.productId,
            requestedQuantity: line.quantity,
            availableQuantity: availableLimit,
          ));
        }

        final finalQuantity = min(line.quantity, availableLimit);
        reconciledLines.add(line.copyWith(
          unitPricePaise: serverProduct.pricePaise,
          quantity: finalQuantity,
          maxPerOrder: availableLimit,
        ));
      }
    }

    // 2. Reconcile coupon if present
    Coupon? reconciledCoupon = cart.coupon;
    if (cart.coupon != null) {
      try {
        final refreshed = await couponApi.validate(cart.coupon!.code);
        reconciledCoupon = refreshed;
      } on ClientException catch (e) {
        if (e.code == 'COUPON_EXPIRED' || e.code == 'COUPON_NOT_FOUND') {
          changes.add(CouponRemoved(
            code: cart.coupon!.code,
            reason: e.code == 'COUPON_NOT_FOUND' ? 'NOT_FOUND' : 'EXPIRED',
          ));
          reconciledCoupon = null;
        } else {
          rethrow;
        }
      }
    }

    final reconciledCart = Cart(lines: reconciledLines, coupon: reconciledCoupon);
    return ReconciliationResult(cart: reconciledCart, changes: changes);
  }
}
