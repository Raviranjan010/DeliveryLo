import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/data/config_repository.dart';
import 'package:quickkart/features/app_config/domain/app_config.dart';
import 'package:quickkart/features/app_config/presentation/app_config_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  group('Part C: Remote Configuration & Live Updates', () {
    late TestHarness h;

    setUp(() => h = TestHarness());
    tearDown(() => h.dispose());

    test('ConfigRepository persists successful config and loads it when offline', () async {
      final repo = h.read(configRepositoryProvider);

      // Publish a custom config to the server
      h.server.publishConfig({
        'delivery_fee_paise': 3500,
        'free_delivery_threshold_paise': 24900,
      });

      // 1. Initial load online: should fetch and cache
      final onlineConfig = await repo.load();
      expect(onlineConfig.deliveryFeePaise, 3500);
      expect(onlineConfig.freeDeliveryThresholdPaise, 24900);

      // Verify that values were written to device storage
      final cachedRaw = await h.store.getString('remote_config.v1');
      expect(cachedRaw, isNotNull);
      expect(cachedRaw, contains('3500'));

      // 2. Go offline
      h.server.chaos.offline = true;

      // 3. Load while offline: should load the cached config rather than failing
      final offlineConfig = await repo.load();
      expect(offlineConfig.deliveryFeePaise, 3500);
      expect(offlineConfig.freeDeliveryThresholdPaise, 24900);
    });

    test('ConfigRepository returns defaults when offline with empty cache without throwing', () async {
      // Empty store, offline server
      h.server.chaos.offline = true;
      final repo = h.read(configRepositoryProvider);

      final config = await repo.load();
      expect(config.deliveryFeePaise, AppConfig.defaults().deliveryFeePaise);
      expect(config.freeDeliveryThresholdPaise, AppConfig.defaults().freeDeliveryThresholdPaise);
      expect(config.storeOpen, isTrue);
    });

    test('AppConfigController receives live config updates in bare container without leaks', () async {
      // Read controller in bare ProviderContainer (independent of widgets)
      final initialConfig = h.read(appConfigControllerProvider);
      expect(initialConfig.storeOpen, isTrue);

      final initialListeners = h.server.configListenerCount;
      expect(initialListeners, greaterThanOrEqualTo(1));

      // Publish new config from the console
      h.server.publishConfig({
        'store_open': false,
        'store_closed_message': 'Temporarily closed for maintenance',
      });

      // Allow microtasks / event loop to process stream notification
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final updatedConfig = h.read(appConfigControllerProvider);
      expect(updatedConfig.storeOpen, isFalse,
          reason: 'AppConfigController must update live without app restart');
      expect(updatedConfig.storeClosedMessage, 'Temporarily closed for maintenance');

      // Dispose container and verify listeners are cleaned up
      h.dispose();
      expect(h.server.configListenerCount, 0,
          reason: 'Disposing container must cancel stream subscription without leak');
    });
  });
}
