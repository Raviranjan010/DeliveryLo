import '../../../core/utils/money.dart';
import '../domain/product.dart';

/// Maps the API representation of a product (see API_CONTRACT.md) to the
/// domain [Product].
class ProductDto {
  const ProductDto._();

  static Product fromJson(Map<String, dynamic> json) {
    final pricePaise = rupeesToPaise(json['price'] as num);
    final rawMrp = json['mrp'];
    final mrpPaise = rawMrp == null ? pricePaise : rupeesToPaise(rawMrp as num);
    final rawStock = json['stock'];
    final stock = rawStock is int ? rawStock : int.parse(rawStock as String);

    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['categoryId'] as String,
      emoji: json['emoji'] as String? ?? '🛒',
      unit: json['unit'] as String? ?? '',
      pricePaise: pricePaise,
      mrpPaise: mrpPaise,
      stock: stock,
      maxPerOrder: json['maxPerOrder'] as int? ?? 10,
    );
  }

  static List<Product> listFromJson(Object? json) => (json as List)
      .map((e) => fromJson(e as Map<String, dynamic>))
      .toList();
}
