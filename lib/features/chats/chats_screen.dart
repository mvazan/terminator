import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/chat_policy.dart';
import '../../domain/models.dart';
import 'chat_screen.dart';

/// All chats: for every tournament its team chat, plus a day chat for each
/// day that has ordered starts. Locked ones live in the archive section.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournaments = ref.watch(tournamentsProvider).value ?? const [];
    final orders = ref.watch(ordersProvider).value ?? const [];
    final orderSlots =
        ref.watch(orderSlotsProvider).value ?? const <String, Set<String>>{};
    final slots = ref.watch(slotsProvider).value ?? const [];
    final mutes = ref.watch(myMutesProvider).value ?? const <String>{};

    final slotById = {for (final s in slots) s.id: s};
    final now = today();

    // Days with ordered starts, per tournament.
    final orderedDays = <String, Set<Day>>{};
    for (final order in orders) {
      if (!order.isActive) continue;
      for (final slotId in orderSlots[order.id] ?? const <String>{}) {
        final slot = slotById[slotId];
        if (slot != null) {
          orderedDays.putIfAbsent(order.tournamentId, () => {}).add(slot.date);
        }
      }
    }

    final open = <_ChatTileData>[];
    final archived = <_ChatTileData>[];
    for (final t in tournaments) {
      final chats = <_ChatTileData>[
        _ChatTileData(tournament: t),
        for (final day in (orderedDays[t.id] ?? const <Day>{}).toList()
          ..sort())
          _ChatTileData(tournament: t, day: day),
      ];
      for (final chat in chats) {
        (isChatLocked(tournament: t, day: chat.day, today: now)
                ? archived
                : open)
            .add(chat);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Chaty')),
      body: (open.isEmpty && archived.isEmpty)
          ? const Center(
              child: Text('Žádné chaty.\nZaloží se s prvním turnajem.',
                  textAlign: TextAlign.center))
          : ListView(
              children: [
                for (final chat in open)
                  _ChatTile(data: chat, mutes: mutes),
                if (archived.isNotEmpty)
                  ExpansionTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: Text('Archiv (${archived.length})'),
                    children: [
                      for (final chat in archived)
                        _ChatTile(data: chat, mutes: mutes, locked: true),
                    ],
                  ),
              ],
            ),
    );
  }
}

class _ChatTileData {
  const _ChatTileData({required this.tournament, this.day});

  final Tournament tournament;
  final Day? day;
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.data,
    required this.mutes,
    this.locked = false,
  });

  final _ChatTileData data;
  final Set<String> mutes;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final t = data.tournament;
    final day = data.day;
    final muted = mutes.contains(muteKey(t.id, day));

    return ListTile(
      leading: Icon(day == null ? Icons.groups : Icons.event),
      title: Text(day == null ? t.name : '${t.name} — ${dayLabel(day)}'),
      subtitle: Text(day == null
          ? 'chat k turnaji · celá parta'
          : 'chat hracího dne · účastníci'),
      trailing: locked
          ? const Icon(Icons.lock_outline, size: 18)
          : IconButton(
              icon: Icon(
                muted
                    ? Icons.notifications_off
                    : Icons.notifications_active_outlined,
                size: 20,
              ),
              tooltip: muted ? 'Zapnout upozornění' : 'Ztlumit',
              onPressed: () => tryAction(
                  context, () => Api.setMuted(t.id, day, !muted)),
            ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(tournamentId: t.id, day: day),
        ),
      ),
    );
  }
}
