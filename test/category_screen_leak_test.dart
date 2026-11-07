import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/core/providers.dart';
import 'package:quickkart/features/catalog/domain/product.dart';
import 'package:quickkart/features/catalog/presentation/category_screen.dart';

import 'helpers/test_harness.dart';

void main() {
  group('BUG-8: CategoryScreen stream listener leak', () {
    late TestHarness h;

    setUp(() => h = TestHarness());
    tearDown(() => h.dispose());

    testWidgets('reproduce BUG-8: CategoryScreen does not leak config listener after dispose', (tester) async {
      final category = const Category(id: 'fruits', name: 'Fruits & Veggies', emoji: '🥦');
      final initialListeners = h.server.configListenerCount;

      // Pump the CategoryScreen inside a provider scope
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: MaterialApp(
            home: CategoryScreen(category: category),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Dispose the widget by replacing it
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: h.container,
          child: const MaterialApp(home: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();

      // In the buggy code, CategoryScreen subscribed to remoteUpdates in initState
      // and never cancelled the subscription on dispose, leaking listeners!
      expect(h.server.configListenerCount, initialListeners,
          reason: 'CategoryScreen must not leak config stream listeners when disposed');
    });
  });
}
