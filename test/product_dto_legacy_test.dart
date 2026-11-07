import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/catalog/data/catalog_repository.dart';
import 'package:quickkart/features/catalog/data/product_dto.dart';

import 'helpers/test_harness.dart';

void main() {
  group('BUG-4: Legacy product deserialization in ProductDto', () {
    late TestHarness h;

    setUp(() => h = TestHarness());
    tearDown(() => h.dispose());

    test('reproduce BUG-4: ProductDto.fromJson crashes on legacy product with null mrp and string stock', () {
      final legacyJson = <String, dynamic>{
        'id': 'dairy-00',
        'name': 'Toned Milk',
        'categoryId': 'dairy',
        'emoji': '🥛',
        'unit': '500 ml',
        'price': 29.0,
        'mrp': null, // legacy format omits mrp when equal to price
        'stock': '120', // legacy format returns string stock
        'maxPerOrder': 6,
      };

      // In the buggy code, this throws a TypeError because mrp is null and stock is String
      final product = ProductDto.fromJson(legacyJson);

      expect(product.id, 'dairy-00');
      expect(product.pricePaise, 2900);
      expect(product.mrpPaise, 2900,
          reason: 'When mrp is null, mrpPaise should default to pricePaise');
      expect(product.stock, 120,
          reason: 'String stock representation must be parsed into an integer');
    });

    test('reproduce BUG-4: loading dairy category succeeds even with legacy products', () async {
      // In the buggy code, getPage('dairy') fails because dairy-00 and dairy-02 are legacy products
      final page = await h.read(catalogRepositoryProvider).getPage(categoryId: 'dairy');
      expect(page.items, isNotEmpty);
      expect(page.items.any((p) => p.id == 'dairy-00'), isTrue);
    });
  });
}
