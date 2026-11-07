import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';

import 'helpers/test_harness.dart';

void main() {
  group('BUG-7: Catalog cache key collision across categories', () {
    late TestHarness h;

    setUp(() => h = TestHarness());
    tearDown(() => h.dispose());

    test('reproduce BUG-7: offline cached page does not collide between categories', () async {
      final repo = h.read(catalogRepositoryProvider);

      // Load fruits online (caches fruits)
      final fruitsPage = await repo.getPage(categoryId: 'fruits');
      expect(fruitsPage.items.first.categoryId, 'fruits');

      // Load beverages online (in buggy code, overwrites 'page.first' with beverages!)
      final bevPage = await repo.getPage(categoryId: 'beverages');
      expect(bevPage.items.first.categoryId, 'beverages');

      // Simulate restart and offline
      h = h.restart();
      h.server.chaos.offline = true;

      // Request fruits offline
      final offlineRepo = h.read(catalogRepositoryProvider);
      final offlineFruits = await offlineRepo.getPage(categoryId: 'fruits');

      // In the buggy code, offlineFruits has items from 'beverages' because
      // the cacheKey was just 'page.first' without categoryId!
      expect(offlineFruits.items.first.categoryId, 'fruits',
          reason: 'Offline cache for fruits must not be corrupted by beverages cache');
      expect(offlineFruits.fromCache, isTrue);
    });
  });
}
