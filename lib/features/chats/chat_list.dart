/// The chat-list model: which chats exist for me, their unread counts and
/// last-message previews. One provider so the list screen and the bottom-bar
/// badge can't drift apart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/local_prefs.dart';
import '../../data/providers.dart';
import '../../domain/chat_policy.dart';
import '../../domain/models.dart';

class ChatTileModel {
  const ChatTileModel({
    this.tournament,
    this.day,
    this.memberCount,
    required this.unread,
    this.lastMessage,
    required this.activity,
    this.locked = false,
    this.venueName = '',
  });

  /// null = the team-wide chat.
  final Tournament? tournament;
  final Day? day;

  /// The tournament's venue — chats are titled venue-first, like tournaments.
  final String venueName;

  /// Members of a day chat (null for tournament/team chats).
  final int? memberCount;
  final int unread;
  final ChatMessage? lastMessage;
  final DateTime activity;
  final bool locked;

  String get key => muteKey(tournament?.id ?? teamChatId, day);
}

class ChatListModel {
  const ChatListModel({
    required this.team,
    required this.open,
    required this.archived,
  });

  final ChatTileModel team;
  final List<ChatTileModel> open;
  final List<ChatTileModel> archived;

  /// Unread across the chats the user actually follows (archive excluded).
  int get totalUnread =>
      team.unread + open.fold(0, (sum, c) => sum + c.unread);
}

final chatListProvider = Provider<ChatListModel>((ref) {
  final tournaments = ref.watch(tournamentsProvider).value ?? const [];
  final orders = ref.watch(ordersProvider).value ?? const [];
  final orderSlots = ref.watch(orderSlotsProvider).value ??
      const <String, Map<String, int?>>{};
  final slots = ref.watch(slotsProvider).value ?? const [];
  final slotById = {for (final s in slots) s.id: s};
  final venues = ref.watch(venuesProvider).value ?? const [];
  final venueById = {for (final v in venues) v.id: v};
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

  // Last message and unread count per chat key; the team chat rides along
  // under its sentinel key.
  final messages = ref.watch(allMessagesProvider).value ?? const [];
  final teamMessages = ref.watch(teamMessagesProvider).value ?? const [];
  final reads = ref.watch(chatReadsProvider);
  final uid = ref.watch(currentUserIdProvider);
  final lastMsg = <String, ChatMessage>{};
  final unread = <String, int>{};
  for (final msg in [...messages, ...teamMessages]) {
    final key = muteKey(msg.tournamentId, msg.day);
    final last = lastMsg[key];
    if (last == null || msg.createdAt.isAfter(last.createdAt)) {
      lastMsg[key] = msg;
    }
    final readAt = reads[key];
    if (msg.userId != uid &&
        (readAt == null || msg.createdAt.isAfter(readAt))) {
      unread[key] = (unread[key] ?? 0) + 1;
    }
  }

  // Day chats are closed groups — only the ones I'm a member of.
  final membership = ref.watch(dayChatMembershipProvider);

  final open = <ChatTileModel>[];
  final archived = <ChatTileModel>[];
  for (final t in tournaments) {
    // The tournament-wide chat exists for every tournament, so most are
    // empty — show it only once it has messages (start it from the
    // tournament detail). Day chats are deliberate (an ordered day) and few,
    // so they show even empty.
    final candidates = <({Day? day, int? memberCount})>[
      if (lastMsg.containsKey(muteKey(t.id, null)))
        (day: null, memberCount: null),
      for (final day in (orderedDays[t.id] ?? const <Day>{}).toList()..sort())
        if (uid != null &&
            (membership[muteKey(t.id, day)]?.contains(uid) ?? false))
          (
            day: day,
            memberCount: membership[muteKey(t.id, day)]?.members.length ?? 0,
          ),
    ];
    for (final c in candidates) {
      final key = muteKey(t.id, c.day);
      final locked = isChatLocked(tournament: t, day: c.day, today: now);
      (locked ? archived : open).add(ChatTileModel(
        tournament: t,
        day: c.day,
        memberCount: c.memberCount,
        venueName: venueById[t.venueId]?.name ?? '?',
        unread: locked ? 0 : (unread[key] ?? 0),
        lastMessage: lastMsg[key],
        // A chat without messages counts as active at its creation — a
        // brand-new chat starts near the top, not last.
        activity: lastMsg[key]?.createdAt ??
            chatCreatedAt[key] ??
            DateTime.fromMillisecondsSinceEpoch(0),
        locked: locked,
      ));
    }
  }

  int byActivity(ChatTileModel a, ChatTileModel b) =>
      b.activity.compareTo(a.activity);
  open.sort(byActivity);
  archived.sort(byActivity);

  final teamKey = muteKey(teamChatId, null);
  return ChatListModel(
    team: ChatTileModel(
      unread: unread[teamKey] ?? 0,
      lastMessage: lastMsg[teamKey],
      activity:
          lastMsg[teamKey]?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    ),
    open: open,
    archived: archived,
  );
});
