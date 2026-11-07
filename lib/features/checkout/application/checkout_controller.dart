import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../app_config/presentation/app_config_controller.dart';
import '../../cart/application/cart_controller.dart';
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
  @override
  CheckoutState build() => const CheckoutState();

  Future<CheckoutResult> placeOrder() async {
    state = const CheckoutState(isPlacingOrder: true);
    final result = await _placeOrder(retryOnTimeout: true);
    state = CheckoutState(lastResult: result);
    return result;
  }

  Future<CheckoutResult> _placeOrder({required bool retryOnTimeout}) async {
    final cart = ref.read(cartControllerProvider);
    if (cart.isEmpty) {
      return const CheckoutFailure('Your cart is empty');
    }
    final pricing =
        CartPricing.compute(cart, ref.read(appConfigControllerProvider));

    try {
      final order = await ref.read(orderApiProvider).placeOrder(cart, pricing);
      await ref.read(cartControllerProvider.notifier).clear();
      ref.invalidate(ordersProvider);
      return CheckoutSuccess(order);
    } on ApiTimeoutException {
      // Slow networks are common; give it one more go before bothering
      // the user.
      if (retryOnTimeout) return _placeOrder(retryOnTimeout: false);
      return const CheckoutFailure(
        'The request timed out. Please try again.',
        canRetry: true,
      );
    } on ApiException catch (e) {
      return CheckoutFailure(e.message, canRetry: e.isTransient);
    }
  }
}
