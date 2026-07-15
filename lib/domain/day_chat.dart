/// Day-chat membership: who is in a closed day chat. Members = rostered
/// players that day ∪ the order creator ∪ invited fans, minus those who left.
/// Pure so it can be unit-tested without the backend.
library;

import 'models.dart';

/// A fan invited to a day chat (additive membership).
class DayChatFan {
  const DayChatFan({
    required this.tournamentId,
    required this.day,
    required this.userId,
  });

  final String tournamentId;
  final Day day;
  final String userId;

  factory DayChatFan.fromJson(Map<String, dynamic> j) => DayChatFan(
        tournamentId: j['tournament_id'] as String,
        day: Day.parse(j['day'] as String),
        userId: j['user_id'] as String,
      );
}

/// Someone who left a day chat (subtractive — overrides the other sources).
class DayChatLeaver {
  const DayChatLeaver({
    required this.tournamentId,
    required this.day,
    required this.userId,
  });

  final String tournamentId;
  final Day day;
  final String userId;

  factory DayChatLeaver.fromJson(Map<String, dynamic> j) => DayChatLeaver(
        tournamentId: j['tournament_id'] as String,
        day: Day.parse(j['day'] as String),
        userId: j['user_id'] as String,
      );
}

/// The membership of one day chat, split by source (a user can be more than
/// one). [members] applies the leaver subtraction.
class DayChatMembership {
  final Set<String> players = {}; // rostered that day
  final Set<String> creators = {}; // creators of that day's active orders
  final Set<String> fans = {}; // invited fans
  final Set<String> leavers = {}; // opted out

  /// Rostered players are always in; only the creator/fans can leave.
  Set<String> get members =>
      {...players, ...{...creators, ...fans}.difference(leavers)};

  bool contains(String uid) =>
      players.contains(uid) ||
      ((creators.contains(uid) || fans.contains(uid)) &&
          !leavers.contains(uid));

  /// A member who is only a fan (not rostered / not the creator) — for the UI
  /// to label "fanoušek" vs "hráč". Can leave.
  bool isFanOnly(String uid) =>
      fans.contains(uid) &&
      !players.contains(uid) &&
      !creators.contains(uid) &&
      !leavers.contains(uid);

  /// Can this member leave? Rostered players stay (they mute instead).
  bool canLeave(String uid) => contains(uid) && !players.contains(uid);
}

/// The chat key matching muteKey(tournamentId, day) for a day chat.
String dayChatKey(String tournamentId, Day day) =>
    '$tournamentId|${day.toSql()}';

/// Membership per day chat, keyed "tournamentId|yyyy-mm-dd". Only day chats
/// that actually exist (have an active order) get an entry; fans/leavers for a
/// vanished chat are ignored.
Map<String, DayChatMembership> dayChatMembershipByChat({
  required List<Order> orders,
  required Map<String, Map<String, int>> orderSlots,
  required List<Slot> slots,
  required List<RosterEntry> rosters,
  required List<DayChatFan> fans,
  required List<DayChatLeaver> leavers,
}) {
  final slotById = {for (final s in slots) s.id: s};
  final rostersBySlot = <String, List<RosterEntry>>{};
  for (final r in rosters) {
    rostersBySlot.putIfAbsent(r.slotId, () => []).add(r);
  }

  final byKey = <String, DayChatMembership>{};
  DayChatMembership at(String tId, Day day) =>
      byKey.putIfAbsent(dayChatKey(tId, day), DayChatMembership.new);

  for (final o in orders) {
    if (!o.isActive) continue;
    for (final slotId in (orderSlots[o.id] ?? const <String, int>{}).keys) {
      final slot = slotById[slotId];
      if (slot == null) continue;
      final m = at(o.tournamentId, slot.date);
      m.creators.add(o.createdBy);
      for (final r in rostersBySlot[slotId] ?? const <RosterEntry>[]) {
        final uid = r.userId;
        if (uid != null) m.players.add(uid);
      }
    }
  }
  for (final f in fans) {
    byKey[dayChatKey(f.tournamentId, f.day)]?.fans.add(f.userId);
  }
  for (final l in leavers) {
    byKey[dayChatKey(l.tournamentId, l.day)]?.leavers.add(l.userId);
  }
  return byKey;
}
