import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/cart/domain/cart.dart';
import 'package:quickkart/features/cart/domain/cart_pricing.dart';
import 'package:quickkart/features/catalog/presentation/catalog_controller.dart';
import 'package:quickkart/features/checkout/data/order_api.dart';
import 'package:quickkart/features/orders/data/order_tracking_repository.dart';

import 'helpers/test_harness.dart';

void main() {
  group('QK-102: Stale response cache on refresh and order placement', () {
    late TestHarness h;

    setUp(() => h = TestHarness());
    tearDown(() => h.dispose());

    test('reproduce QK-102 (part 1): catalog refresh must reflect updated prices from server', () async {
      final controller = h.container.read(catalogControllerProvider('fruits').notifier);

      // Wait for initial load
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final initialTomato = h.container
          .read(catalogControllerProvider('fruits'))
          .items
          .firstWhere((p) => p.id == 'fruits-03');
      expect(initialTomato.pricePaise, 1999);

      // Server updates price of tomato
      h.server.setPrice('fruits-03', 2500);

      // User performs pull-to-refresh
      await controller.refresh();

      final refreshedTomato = h.container
          .read(catalogControllerProvider('fruits'))
          .items
          .firstWhere((p) => p.id == 'fruits-03');

      // In the buggy implementation, ApiClient returns cached 1999 paise response!
      expect(refreshedTomato.pricePaise, 2500,
          reason: 'Pull-to-refresh must bypass/invalidate cache and fetch latest price');
    });

    test('reproduce QK-102 (part 2): newly placed order must appear in orders list without restart', () async {
      // User initially views orders page
      final initialOrders = await h.read(ordersProvider.future);
      expect(initialOrders, isEmpty);

      // Place an order
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
      final pricing = CartPricing.compute(cart, AppConfig.defaults());
      final placedOrder = await h.read(orderApiProvider).placeOrder(cart, pricing);

      // After placing the order, orders list should include the new order
      final ordersAfterPlacement = await h.read(orderApiProvider).getOrders();

      // In the buggy implementation, ApiClient cached the empty /v1/orders response!
      expect(ordersAfterPlacement.map((o) => o.id), contains(placedOrder.id),
          reason: 'Newly placed order must appear in order list without app restart');
    });
  });
}
