import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/config_repository.dart';
import '../domain/app_config.dart';

/// The config the app is currently using. Hydrated in `main.dart` before the
/// first frame.
final appConfigControllerProvider =
    NotifierProvider<AppConfigController, AppConfig>(AppConfigController.new);

class AppConfigController extends Notifier<AppConfig> {
  StreamSubscription<int>? _subscription;
  bool _disposed = false;
  bool _hydrated = false;

  @override
  AppConfig build() {
    _disposed = false;
    _hydrated = false;
    _subscription?.cancel();
    final repo = ref.watch(configRepositoryProvider);
    _subscription = repo.remoteUpdates.listen((_) {
      refresh();
    });

    ref.onDispose(() {
      _disposed = true;
      _subscription?.cancel();
      _subscription = null;
    });

    // Asynchronously self-hydrate so bare ProviderContainer instances
    // receive current server/storage configuration without depending
    // exclusively on main.dart bootstrap.
    Future.microtask(() {
      if (!_disposed && !_hydrated) {
        refresh();
      }
    });

    return AppConfig.defaults();
  }

  /// Used at startup with the config loaded during bootstrap.
  void hydrate(AppConfig config) {
    _hydrated = true;
    state = config;
  }

  Future<void> refresh() async {
    final loaded = await ref.read(configRepositoryProvider).load();
    if (!_disposed) {
      _hydrated = true;
      state = loaded;
    }
  }
}
