import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../push/push.dart';
import 'chats/chat_list.dart';
import 'chats/chats_screen.dart';
import 'home/my_starts_screen.dart';
import 'team/team_screen.dart';
import 'tournaments/tournaments_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
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
    final unread = ref.watch(chatListProvider).totalUnread;
    return Scaffold(
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.sports_score_outlined),
            selectedIcon: Icon(Icons.sports_score),
            label: 'Moje starty',
          ),
          const NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'Turnaje',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.chat_bubble_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.chat_bubble),
            ),
            label: 'Chaty',
          ),
          const NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Tým',
          ),
        ],
      ),
    );
  }
}
