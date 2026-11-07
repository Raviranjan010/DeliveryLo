import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'features/app_config/domain/update_policy.dart';
import 'features/app_config/presentation/app_config_controller.dart';
import 'features/app_config/presentation/force_update_screen.dart';
import 'features/catalog/presentation/home_screen.dart';

class QuickKartApp extends ConsumerWidget {
  const QuickKartApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appVersion = ref.watch(appVersionProvider);
    final config = ref.watch(appConfigControllerProvider);
    final updateRequirement = UpdatePolicy.evaluate(
      currentVersion: appVersion,
      minSupportedVersion: config.minSupportedVersion,
      latestVersion: config.latestVersion,
    );

    return MaterialApp(
      title: 'QuickKart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0C831F),
        scaffoldBackgroundColor: const Color(0xFFF6F7F9),
      ),
      home: updateRequirement == UpdateRequirement.required
          ? ForceUpdateScreen(updateUrl: config.updateUrl)
          : const HomeScreen(),
    );
  }
}
