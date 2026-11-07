import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exceptions.dart';
import '../catalog/data/catalog_repository.dart';
import '../catalog/domain/product.dart';

class SearchState {
  const SearchState({
    this.query = '',
    this.results = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  /// The query the visible [results] belong to.
  final String query;
  final List<Product> results;
  final bool isLoading;
  final String? errorMessage;
}

final searchControllerProvider =
    NotifierProvider<ProductSearchController, SearchState>(
  ProductSearchController.new,
);

class ProductSearchController extends Notifier<SearchState> {
  int _searchSequence = 0;

  @override
  SearchState build() => const SearchState();

  /// Called on every keystroke of the search field.
  Future<void> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchSequence++;
      state = const SearchState();
      return;
    }
    if (trimmed.length < 2) {
      _searchSequence++;
      state = SearchState(query: query, results: const [], isLoading: false);
      return;
    }

    final seq = ++_searchSequence;
    state = SearchState(query: query, results: state.results, isLoading: true);
    try {
      final results =
          await ref.read(catalogRepositoryProvider).search(trimmed);
      if (seq == _searchSequence) {
        state = SearchState(query: query, results: results);
      }
    } on ApiException catch (e) {
      if (seq == _searchSequence) {
        state = SearchState(query: query, errorMessage: e.message);
      }
    }
  }

  void clear() {
    _searchSequence++;
    state = const SearchState();
  }
}
