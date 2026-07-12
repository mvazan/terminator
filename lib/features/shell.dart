import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../push/push.dart';
import 'chats/chats_screen.dart';
import 'home/my_starts_screen.dart';
import 'team/team_screen.dart';
import 'tournaments/tournaments_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Notification taps navigate only once the signed-in shell is on screen;
    // this also fires a tap that cold-started the app. switchTab lets a tap
    // change the bottom-nav tab (e.g. new_member → Tým).
    WidgetsBinding.instance.addPostFrameCallback((_) => Push.shellReady(true,
        switchTab: (i) {
          if (mounted) setState(() => _tab = i);
        }));
  }

  @override
  void dispose() {
    Push.shellReady(false);
    super.dispose();
  }

  static const _screens = [
    MyStartsScreen(),
    TournamentsScreen(),
    ChatsScreen(),
    TeamScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const _OfflineBanner(),
          Expanded(child: IndexedStack(index: _tab, children: _screens)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sports_score_outlined),
            selectedIcon: Icon(Icons.sports_score),
            label: 'Moje starty',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'Turnaje',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chaty',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Tým',
          ),
        ],
      ),
    );
  }
}

/// Slim banner shown while the realtime socket is down for more than a few
/// seconds — the screens below keep showing the last cached data (read-only).
/// Debounced so routine reconnects don't flash it.
class _OfflineBanner extends ConsumerStatefulWidget {
  const _OfflineBanner();

  @override
  ConsumerState<_OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends ConsumerState<_OfflineBanner> {
  bool _show = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onConnected(bool connected) {
    _debounce?.cancel();
    if (connected) {
      if (_show) setState(() => _show = false);
    } else {
      _debounce = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _show = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(realtimeConnectedProvider,
        (_, next) => _onConnected(next.value ?? true));
    if (!_show) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.cloud_off, size: 16, color: scheme.onSurfaceVariant),
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
    );
  }
}
