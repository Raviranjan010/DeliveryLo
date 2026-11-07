import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../checkout/data/order_api.dart';
import '../../checkout/domain/order.dart';

final orderTrackingRepositoryProvider = Provider<OrderTrackingRepository>(
  (ref) => OrderTrackingRepository(
    orderApi: ref.watch(orderApiProvider),
    watchOrderDocument: (id) => ref.read(mockServerProvider).watchOrder(id),
    pushMessages: () => ref.read(mockServerProvider).pushMessages,
  ),
);

/// Order history + live tracking.
///
/// [watchOrderDocument] behaves like a Firestore document snapshot listener
/// and [pushMessages] like `FirebaseMessaging.onMessage` (foreground FCM).
class OrderTrackingRepository {
  OrderTrackingRepository({
    required this.orderApi,
    required this.watchOrderDocument,
    required this.pushMessages,
  });

  final OrderApi orderApi;
  final Stream<Map<String, dynamic>> Function(String orderId)
      watchOrderDocument;
  final Stream<Map<String, dynamic>> Function() pushMessages;

  Future<List<Order>> getOrders({bool forceRefresh = false}) =>
      orderApi.getOrders(forceRefresh: forceRefresh);

  /// ## TODO(F3, optional) - implement
  ///
  /// Emits the order immediately and then every time its status changes.
  Stream<Order> watchOrder(String orderId) {
    throw UnimplementedError('F3: implement OrderTrackingRepository.watchOrder');
  }
}

final ordersProvider = FutureProvider<List<Order>>(
  (ref) => ref.watch(orderTrackingRepositoryProvider).getOrders(forceRefresh: true),
);
