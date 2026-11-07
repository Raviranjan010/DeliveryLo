import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/application/cart_controller.dart';
import '../../cart/application/cart_reconciler.dart';
import '../../cart/domain/cart.dart';
import '../../cart/domain/cart_pricing.dart';
import '../../cart/domain/reconciliation.dart';
import '../../orders/data/order_tracking_repository.dart';
import '../data/order_api.dart';
import '../domain/order.dart';

/// Result of [CheckoutController.placeOrder].
sealed class CheckoutResult {
  const CheckoutResult();
}

/// The order was created. The cart has been cleared.
class CheckoutSuccess extends CheckoutResult {
  const CheckoutSuccess(this.order);

  final Order order;
}

/// The cart changed on the server; the user must review it before trying
/// again. The cart in [CartController] has already been updated to
/// `reconciliation.cart`.
class CheckoutNeedsReview extends CheckoutResult {
  const CheckoutNeedsReview(this.reconciliation);

  final ReconciliationResult reconciliation;
}

/// The order was not placed.
class CheckoutFailure extends CheckoutResult {
  const CheckoutFailure(this.message, {this.canRetry = false});

  final String message;
  final bool canRetry;
}

class CheckoutState {
  const CheckoutState({this.isPlacingOrder = false, this.lastResult});

  final bool isPlacingOrder;
  final CheckoutResult? lastResult;
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(
  CheckoutController.new,
);

class CheckoutController extends Notifier<CheckoutState> {
  static const _uuid = Uuid();

  String? _idempotencyKey;
  Cart? _logicalOrderCart;

  @override
  CheckoutState build() => const CheckoutState();

  /// Places the order safely using an idempotency key and server reconciliation.
  Future<CheckoutResult> placeOrder() async {
    // 1. Prevent concurrent duplicate checkout operations
    if (state.isPlacingOrder) {
      return state.lastResult ??
          const CheckoutFailure('An order is already being placed');
    }

    // 2. Enforce store closure kill switch before any network call
    final config = ref.read(appConfigControllerProvider);
    if (!config.storeOpen) {
      final failure = CheckoutFailure(
        config.storeClosedMessage,
        canRetry: false,
      );
      state = CheckoutState(lastResult: failure);
      return failure;
    }

    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) {
      const failure = CheckoutFailure('Your cart is empty');
      state = const CheckoutState(lastResult: failure);
      return failure;
    }

    state = const CheckoutState(isPlacingOrder: true);
    final result = await _executeOrderFlow(retryOnTimeout: true);
    state = CheckoutState(lastResult: result);
    return result;
  }

  Future<CheckoutResult> _executeOrderFlow({required bool retryOnTimeout}) async {
    var cart = ref.read(cartControllerProvider);

    // If this is a retry of the same in-flight logical order, bypass pre-checkout
    // reconciliation and submit directly using the existing idempotency key.
    // If the server already created the order on the first attempt, the server
    // has already decremented inventory. Running reconcile() would see stock: 0,
    // falsely report OutOfStock, and lose the order.
    if (_idempotencyKey != null && _logicalOrderCart == cart) {
      final pricing =
          CartPricing.compute(cart, ref.read(appConfigControllerProvider));
      return _sendOrderWithRetry(
        cart: cart,
        pricing: pricing,
        idempotencyKey: _idempotencyKey!,
        retryOnTimeout: retryOnTimeout,
      );
    }

    // 3. Pre-checkout reconciliation: reconcile cart against current server state
    try {
      final recon = await ref.read(cartReconcilerProvider).reconcile(cart);
      if (recon.requiresUserReview) {
        // Changes require explicit user review (price increase, stock drop, coupon drop)
        await ref.read(cartControllerProvider.notifier).replace(recon.cart);
        _resetIdempotency();
        return CheckoutNeedsReview(recon);
      } else if (recon.hasChanges) {
        // Silent changes only (e.g. price decrease per BUSINESS_RULES.md §5)
        await ref.read(cartControllerProvider.notifier).replace(recon.cart);
        cart = recon.cart;
      }
    } on NetworkException {
      return const CheckoutFailure(
        'You appear to be offline. Please check your internet connection.',
        canRetry: true,
      );
    } on ApiException catch (e) {
      return CheckoutFailure(e.message, canRetry: e.isTransient);
    }

    // 4. Generate idempotency key for this new logical order payload
    _idempotencyKey = _uuid.v4();
    _logicalOrderCart = cart;

    final pricing =
        CartPricing.compute(cart, ref.read(appConfigControllerProvider));

    return _sendOrderWithRetry(
      cart: cart,
      pricing: pricing,
      idempotencyKey: _idempotencyKey!,
      retryOnTimeout: retryOnTimeout,
    );
  }

  Future<CheckoutResult> _sendOrderWithRetry({
    required Cart cart,
    required CartPricing pricing,
    required String idempotencyKey,
    required bool retryOnTimeout,
  }) async {
    try {
      final order = await ref.read(orderApiProvider).placeOrder(
            cart,
            pricing,
            idempotencyKey: idempotencyKey,
          );

      // Order confirmed: clear idempotency session and empty cart
      _resetIdempotency();
      await ref.read(cartControllerProvider.notifier).clear();
      ref.read(apiClientProvider).invalidateCache('/v1/orders');
      ref.invalidate(ordersProvider);

      return CheckoutSuccess(order);
    } on ApiTimeoutException {
      // Automatic immediate retry with SAME idempotency key and SAME payload
      if (retryOnTimeout) {
        return _sendOrderWithRetry(
          cart: cart,
          pricing: pricing,
          idempotencyKey: idempotencyKey,
          retryOnTimeout: false,
        );
      }
      return const CheckoutFailure(
        'The request timed out. Your order may have been placed. '
        'Check My orders or tap to retry.',
        canRetry: true,
      );
    } on ClientException catch (e) {
      // 409 Conflict: prices/stock/coupon changed right at order submission
      if (e.statusCode == 409 ||
          e.code == 'PRICE_CHANGED' ||
          e.code == 'PRODUCT_UNAVAILABLE' ||
          e.code == 'INSUFFICIENT_STOCK' ||
          e.code == 'COUPON_INVALID' ||
          e.code == 'TOTAL_MISMATCH') {
        try {
          final recon = await ref.read(cartReconcilerProvider).reconcile(cart);
          await ref.read(cartControllerProvider.notifier).replace(recon.cart);
          _resetIdempotency();
          return CheckoutNeedsReview(recon);
        } catch (_) {
          return CheckoutFailure(e.message, canRetry: true);
        }
      }

      if (e.code == 'STORE_CLOSED') {
        return CheckoutFailure(e.message, canRetry: false);
      }

      if (e.code == 'IDEMPOTENCY_KEY_REUSED') {
        _resetIdempotency();
        return const CheckoutFailure(
          'Checkout session expired. Please review your cart and try again.',
          canRetry: true,
        );
      }

      return CheckoutFailure(e.message, canRetry: false);
    } on NetworkException {
      return const CheckoutFailure(
        'You appear to be offline. Please check your internet connection.',
        canRetry: true,
      );
    } on ApiException catch (e) {
      return CheckoutFailure(e.message, canRetry: e.isTransient);
    }
  }

  void _resetIdempotency() {
    _idempotencyKey = null;
    _logicalOrderCart = null;
  }
}
