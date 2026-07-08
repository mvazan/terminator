import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/local_prefs.dart';
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
    final orderSlots = ref.watch(orderSlotsProvider).value ??
        const <String, Map<String, int?>>{};
    final slots = ref.watch(slotsProvider).value ?? const [];
    final mutes = ref.watch(myMutesProvider).value ?? const <String>{};

    final slotById = {for (final s in slots) s.id: s};
    final now = today();

    // Days with ordered starts, per tournament — remembering when each day
    // chat came into existence (= when its first order was placed).
    final orderedDays = <String, Set<Day>>{};
    final chatCreatedAt = <String, DateTime>{
      for (final t in tournaments) muteKey(t.id, null): t.createdAt,
    };
    for (final order in orders) {
      if (!order.isActive) continue;
      final orderTime = order.orderedAt ?? order.createdAt;
      for (final slotId
          in (orderSlots[order.id] ?? const <String, int?>{}).keys) {
        final slot = slotById[slotId];
        if (slot != null) {
          orderedDays.putIfAbsent(order.tournamentId, () => {}).add(slot.date);
          final key = muteKey(order.tournamentId, slot.date);
          final existing = chatCreatedAt[key];
          if (existing == null || orderTime.isBefore(existing)) {
            chatCreatedAt[key] = orderTime;
          }
        }
      }
    }

    // Last activity and unread count per chat ("tournamentId|day" key).
    final messages = ref.watch(allMessagesProvider).value ?? const [];
    final reads = ref.watch(chatReadsProvider);
    final uid = currentUserId;
    final lastAt = <String, DateTime>{};
    final unread = <String, int>{};
    for (final msg in messages) {
      final key = muteKey(msg.tournamentId, msg.day);
      final last = lastAt[key];
      if (last == null || msg.createdAt.isAfter(last)) {
        lastAt[key] = msg.createdAt;
      }
      final readAt = reads[key];
      if (msg.userId != uid &&
          (readAt == null || msg.createdAt.isAfter(readAt))) {
        unread[key] = (unread[key] ?? 0) + 1;
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

    // Most recently active first. A chat without messages counts as active
    // at its creation — a brand-new chat starts near the top, not last.
    DateTime activity(_ChatTileData c) {
      final key = muteKey(c.tournament.id, c.day);
      return lastAt[key] ??
          chatCreatedAt[key] ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }

    int byActivity(_ChatTileData a, _ChatTileData b) =>
        activity(b).compareTo(activity(a));

    open.sort(byActivity);
    archived.sort(byActivity);

    return Scaffold(
      appBar: AppBar(title: const Text('Chaty')),
      body: (open.isEmpty && archived.isEmpty)
          ? const Center(
              child: Text('Žádné chaty.\nZaloží se s prvním turnajem.',
                  textAlign: TextAlign.center))
          : ListView(
              children: [
                for (final chat in open)
                  _ChatTile(
                    data: chat,
                    mutes: mutes,
                    unread:
                        unread[muteKey(chat.tournament.id, chat.day)] ?? 0,
                  ),
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
    this.unread = 0,
    this.locked = false,
  });

  final _ChatTileData data;
  final Set<String> mutes;
  final int unread;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final t = data.tournament;
    final day = data.day;
    final muted = mutes.contains(muteKey(t.id, day));

    return ListTile(
      leading: Badge(
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: Icon(day == null ? Icons.groups : Icons.event),
      ),
      title: Text(
        day == null ? t.name : '${t.name} — ${dayLabel(day)}',
        style: unread > 0
            ? const TextStyle(fontWeight: FontWeight.w700)
            : null,
      ),
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
