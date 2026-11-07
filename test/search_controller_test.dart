import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/search/search_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  group('BUG-9: ProductSearchController single-character crash and race conditions', () {
    late TestHarness h;

    setUp(() => h = TestHarness());
    tearDown(() => h.dispose());

    test('reproduce BUG-9: 1-character query does not call API and trigger 400 error', () async {
      final controller = h.read(searchControllerProvider.notifier);

      // Typing a single character
      await controller.search('m');

      final state = h.read(searchControllerProvider);

      // In the buggy code, errorMessage is "Search query must have at least 2 characters"
      expect(state.errorMessage, isNull,
          reason: '1-character search should not fail with 400 error');
      expect(state.results, isEmpty);
      expect(state.isLoading, isFalse);
    });

    test('reproduce BUG-9: out-of-order query responses do not overwrite newer results', () async {
      final controller = h.read(searchControllerProvider.notifier);

      // Start search for "banana" and then quickly "apple"
      final f1 = controller.search('banana');
      final f2 = controller.search('apple');

      await Future.wait([f1, f2]);

      final state = h.read(searchControllerProvider);
      expect(state.query, 'apple');
      expect(state.results.every((p) => p.name.toLowerCase().contains('apple')), isTrue,
          reason: 'Latest query results must be displayed, not overwritten by earlier query');
    });
  });
}
