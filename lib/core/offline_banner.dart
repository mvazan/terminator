import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/live_refresh.dart';
import '../data/providers.dart';

/// Shows a slim banner above [child] while the realtime socket is down for
/// more than a few seconds — the screens below keep showing the last cached
/// data (read-only). Mounted via MaterialApp.builder, so it overlays EVERY
/// screen (detail, calendar, map…), not just the shell. Debounced so routine
/// reconnects don't flash it, and inert while signed out (the socket only
/// connects once the data streams subscribe, so pre-login "disconnected" is
/// normal, not offline).
///
/// The banner consumes the status-bar inset itself (SafeArea) and REMOVES the
/// top padding from [child] — screens' AppBars would otherwise pad for a
/// status bar the banner already sits under, doubling the gap.
class OfflineBanner extends ConsumerStatefulWidget {
  const OfflineBanner({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<OfflineBanner> {
  /// Kolik socketu tolerujeme, než přiznáme offline: při běžném výpadku
  /// krátce, po probuzení appky víc — tam je odpojení normální stav
  /// (Supabase socket v pozadí vědomě zavírá) a spojení se teprve navazuje.
  static const _dropGrace = Duration(seconds: 3);
  static const _wakeGrace = Duration(seconds: 6);

  bool _show = false;
  Timer? _debounce;
  StreamSubscription<void>? _wake;

  @override
  void initState() {
    super.initState();
    _wake = LiveRefresh.stream.listen((_) => _onWake());
  }

  @override
  void dispose() {
    _wake?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  void _onConnected(bool connected) {
    _debounce?.cancel();
    if (connected) {
      if (_show) setState(() => _show = false);
    } else {
      _debounce = Timer(_dropGrace, _showIfStillDown);
    }
  }

  /// Appka se vrátila do popředí: schovej případný banner z doby, kdy byla
  /// v pozadí, a dej socketu čas se vrátit, než budeme něco tvrdit.
  void _onWake() {
    _debounce?.cancel();
    if (_show) setState(() => _show = false);
    _debounce = Timer(_wakeGrace, _showIfStillDown);
  }

  void _showIfStillDown() {
    if (!mounted) return;
    final connected = ref.read(realtimeConnectedProvider).value ?? true;
    if (!connected && !_show) setState(() => _show = true);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(currentUserIdProvider) != null;
    ref.listen(realtimeConnectedProvider,
        (_, next) => _onConnected(next.value ?? true));
    if (!_show || !signedIn) return widget.child;

    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: scheme.surfaceContainerHighest,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.cloud_off,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Offline — zobrazují se poslední známá data.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
