import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/app_config/domain/home_layout.dart';

void main() {
  group('HomeLayout.parse contract tests', () {
    test('parses valid json array in specified order', () {
      const raw = '["deals", "banner", "all_products", "categories"]';
      final result = HomeLayout.parse(raw);

      expect(result, [
        HomeSection.deals,
        HomeSection.banner,
        HomeSection.allProducts,
        HomeSection.categories,
      ]);
    });

    test('ignores unknown section identifiers', () {
      const raw = '["banner", "live_stream", "categories", "story_reels", "all_products"]';
      final result = HomeLayout.parse(raw);

      expect(result, [
        HomeSection.banner,
        HomeSection.categories,
        HomeSection.allProducts,
      ]);
    });

    test('deduplicates duplicate sections with first occurrence winning', () {
      const raw = '["deals", "categories", "deals", "banner", "categories"]';
      final result = HomeLayout.parse(raw);

      expect(result, [
        HomeSection.deals,
        HomeSection.categories,
        HomeSection.banner,
      ]);
    });

    test('returns defaultSections on null input', () {
      final result = HomeLayout.parse(null);
      expect(result, HomeLayout.defaultSections);
    });

    test('returns defaultSections on empty or whitespace input', () {
      expect(HomeLayout.parse(''), HomeLayout.defaultSections);
      expect(HomeLayout.parse('   '), HomeLayout.defaultSections);
    });

    test('returns defaultSections on malformed JSON', () {
      expect(HomeLayout.parse('["banner", "deals"'), HomeLayout.defaultSections);
      expect(HomeLayout.parse('{not a list}'), HomeLayout.defaultSections);
    });

    test('returns defaultSections on non-array JSON value', () {
      expect(HomeLayout.parse('{"sections": ["banner"]}'), HomeLayout.defaultSections);
      expect(HomeLayout.parse('123'), HomeLayout.defaultSections);
      expect(HomeLayout.parse('"banner"'), HomeLayout.defaultSections);
    });

    test('returns defaultSections when no known sections are present', () {
      const raw = '["unknown_1", "unknown_2"]';
      final result = HomeLayout.parse(raw);
      expect(result, HomeLayout.defaultSections);
    });
  });
}
