import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../../core/storage/key_value_store.dart';
import '../domain/app_config.dart';

final configRepositoryProvider = Provider<ConfigRepository>(
  (ref) => ConfigRepository(
    ref.watch(apiClientProvider),
    ref.watch(keyValueStoreProvider),
    remoteUpdates: () => ref.read(mockServerProvider).configUpdates,
  ),
);

/// Loads remote config (think: Firebase Remote Config).
class ConfigRepository {
  ConfigRepository(
    this._client,
    this._store, {
    required Stream<int> Function() remoteUpdates,
  }) : _remoteUpdates = remoteUpdates;

  final ApiClient _client;
  final KeyValueStore _store;
  final Stream<int> Function() _remoteUpdates;

  static const _cacheKey = 'remote_config.v1';

  /// Fires (with the new config version) every time config is published
  /// from the console. Equivalent to Firebase's `onConfigUpdated`.
  Stream<int> get remoteUpdates => _remoteUpdates();

  /// Fetches the latest config.
  ///
  /// On success persists the values to storage.
  /// On failure loads the last known good config from storage.
  /// If nothing valid is cached, returns sensible defaults.
  /// Never throws!
  Future<AppConfig> load() async {
    try {
      final json = await _client.get('/v1/config', forceRefresh: true)
          as Map<String, dynamic>;
      final values = (json['values'] as Map).cast<String, Object?>();
      final config = AppConfig.fromValues(values);
      await _store.setString(_cacheKey, jsonEncode(values));
      return config;
    } catch (_) {
      final cachedRaw = await _store.getString(_cacheKey);
      if (cachedRaw != null) {
        try {
          final cachedValues =
              (jsonDecode(cachedRaw) as Map).cast<String, Object?>();
          return AppConfig.fromValues(cachedValues);
        } catch (_) {
          return AppConfig.defaults();
        }
      }
      return AppConfig.defaults();
    }
  }
}
