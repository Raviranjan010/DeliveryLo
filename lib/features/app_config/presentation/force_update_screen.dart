import 'package:flutter/material.dart';

/// Full-screen, non-dismissible blocker when the installed app version is
/// below `min_supported_version`.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key, required this.updateUrl});

  final String updateUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.system_update_rounded,
                  size: 72,
                  color: Color(0xFF0C831F),
                ),
                const SizedBox(height: 24),
                Text(
                  'Update Required',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This version of QuickKart is no longer supported. '
                  'Please update to the latest version to continue shopping.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: const Color(0xFF0C831F),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Opening update link: $updateUrl')),
                    );
                  },
                  child: const Text('Update Now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
