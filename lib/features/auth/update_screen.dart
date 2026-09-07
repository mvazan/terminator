import 'package:flutter/material.dart';

import '../../core/ui.dart';

/// Blocking screen shown when this build is older than the backend's
/// app_config.min_build — the force-update lever for breaking releases.
/// The auth gate swaps the whole app for it the moment the bump arrives
/// (live stream), so an outdated build stops calling the server at once.
class UpdateScreen extends StatelessWidget {
  const UpdateScreen({super.key});

  /// Play listing — where the update lives.
  static const _playUrl =
      'https://play.google.com/store/apps/details?id=cz.kuzelky.terminator';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.system_update, size: 56,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('Je potřeba aktualizace',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                'Tahle verze aplikace už nestačí na novější server.\n'
                'Aktualizuj v Google Play a jedeme dál.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                icon: const Icon(Icons.system_update),
                label: const Text('Otevřít Google Play'),
                onPressed: () => launchWeb(_playUrl),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
