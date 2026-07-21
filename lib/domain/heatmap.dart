/// Availability heatmap and "best picks" — the core assist logic.
///
/// The tournament detail grid shows, per slot, how many members ticked it;
/// slots at or above the tournament minimum glow "orderable". Best picks rank
/// the strongest slots to pre-select when creating a proposal.
library;

import 'models.dart';

class SlotStats {
  const SlotStats({
    required this.slot,
    required this.count,
    required this.isOrderable,
    required this.userIds,
  });

  final Slot slot;
  final int count;

  /// count >= tournament.minPlayers
  final bool isOrderable;
  final Set<String> userIds;
}

class DayStats {
  const DayStats({required this.day, required this.distinctPlayers});

  final Day day;

  /// How many different members can make at least one slot that day.
  final int distinctPlayers;
}

class Heatmap {
  Heatmap._(this.bySlotId, this.byDay, this.maxCount);

  /// Slot id → stats.
  final Map<String, SlotStats> bySlotId;

  /// Sorted day → stats.
  final Map<Day, DayStats> byDay;

  /// Highest slot count anywhere (for normalising cell shading).
  final int maxCount;

  factory Heatmap.build({
    required Tournament tournament,
    required List<Slot> slots,
    required List<Availability> availability,
  }) {
    final usersBySlot = <String, Set<String>>{};
    for (final a in availability) {
      usersBySlot.putIfAbsent(a.slotId, () => <String>{}).add(a.userId);
    }

    final bySlot = <String, SlotStats>{};
    var maxCount = 0;
    for (final slot in slots) {
      final users = usersBySlot[slot.id] ?? const <String>{};
      if (users.length > maxCount) maxCount = users.length;
      bySlot[slot.id] = SlotStats(
        slot: slot,
        count: users.length,
        isOrderable: users.length >= tournament.minPlayers,
        userIds: users,
      );
    }

    final usersByDay = <Day, Set<String>>{};
    for (final stats in bySlot.values) {
      usersByDay
          .putIfAbsent(stats.slot.date, () => <String>{})
          .addAll(stats.userIds);
    }
    final byDay = <Day, DayStats>{
      for (final day in usersByDay.keys.toList()..sort())
        day: DayStats(day: day, distinctPlayers: usersByDay[day]!.length),
    };

    return Heatmap._(bySlot, byDay, maxCount);
  }

  /// 0.0–1.0 shade for a slot cell (0 = nobody, 1 = the most popular slot).
  double intensity(String slotId) {
    if (maxCount == 0) return 0;
    return (bySlotId[slotId]?.count ?? 0) / maxCount;
  }
}

/// Per-tournament interest for list tiles: how many distinct people ticked
/// anything, the strongest single day, and whether [TournamentInterest.mine]
/// — the given user ticked something.
class TournamentInterest {
  const TournamentInterest({
    required this.players,
    required this.bestDayPlayers,
    required this.mine,
  });

  /// Distinct users with at least one tick anywhere in the tournament.
  final int players;

  /// Distinct users on the strongest single day.
  final int bestDayPlayers;

  /// The given user has at least one tick here.
  final bool mine;
}

/// One pass over all slots + availability, keyed by tournament id — cheap
/// enough to feed every tile of the tournament list at once. Venue-full slots
/// are excluded to match the detail grid (which drops them): a tick on a full
/// slot isn't actionable.
Map<String, TournamentInterest> interestByTournament({
  required List<Slot> slots,
  required List<Availability> availability,
  required Day today,
  required Set<String> endedTournamentIds,
  String? uid,
}) {
  // slot id -> (tournament, day). Past days count only for ended tournaments
  // (Odehrané history); a running one summarizes just what's still ahead —
  // matching the detail, which hides its past days. Venue-full slots count
  // too: the grid shows them (they may be full because WE booked them).
  final slotInfo = <String, (String, Day)>{
    for (final s in slots)
      if (endedTournamentIds.contains(s.tournamentId) ||
          !s.date.isBefore(today))
        s.id: (s.tournamentId, s.date),
  };

  final players = <String, Set<String>>{};
  final byDay = <String, Map<Day, Set<String>>>{};
  final mine = <String>{};
  for (final a in availability) {
    final info = slotInfo[a.slotId];
    if (info == null) continue;
    final (tournamentId, day) = info;
    players.putIfAbsent(tournamentId, () => {}).add(a.userId);
    byDay
        .putIfAbsent(tournamentId, () => {})
        .putIfAbsent(day, () => {})
        .add(a.userId);
    if (a.userId == uid) mine.add(tournamentId);
  }

  return {
    for (final id in players.keys)
      id: TournamentInterest(
        players: players[id]!.length,
        bestDayPlayers: byDay[id]!
            .values
            .map((users) => users.length)
            .reduce((a, b) => a > b ? a : b),
        mine: mine.contains(id),
      ),
  };
}

/// Slots worth proposing, strongest first: orderable slots sorted by player
/// count (desc), then by date and time (asc — sooner is better when equal).
List<SlotStats> bestPicks({
  required Heatmap heatmap,
  int limit = 5,
}) {
  final orderable =
      heatmap.bySlotId.values.where((s) => s.isOrderable).toList()
        ..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          if (byCount != 0) return byCount;
          return Slot.compare(a.slot, b.slot);
        });
  return orderable.take(limit).toList();
}

/// Slot specs pre-selected for a new proposal: the best picks that share the
/// strongest day (orders usually bundle several starts on one day).
List<SlotStats> suggestedBundle(Heatmap heatmap) {
  final picks = bestPicks(heatmap: heatmap, limit: 20);
  if (picks.isEmpty) return const [];
  final bestDay = picks.first.slot.date;
  return picks.where((s) => s.slot.date == bestDay).toList()
    ..sort((a, b) => a.slot.time.compareTo(b.slot.time));
}

/// tournamentId -> number of distinct slots that belong to an active (ordered
/// or confirmed) order. Feeds the "3 obj." suffix on the tournament list.
Map<String, int> orderedSlotsByTournament({
  required List<Slot> slots,
  required List<Order> orders,
  required Map<String, Map<String, int>> orderSlots,
  required Day today,
  required Set<String> endedTournamentIds,
}) {
  final slotInfo = {for (final s in slots) s.id: (s.tournamentId, s.date)};
  final byTournament = <String, Set<String>>{};
  for (final order in orders) {
    if (!order.isActive) continue;
    final slotIds = orderSlots[order.id];
    if (slotIds == null) continue;
    for (final slotId in slotIds.keys) {
      final info = slotInfo[slotId];
      if (info == null) continue;
      final (tid, date) = info;
      // Past ordered slots count only for ended tournaments (see above).
      if (!endedTournamentIds.contains(tid) && date.isBefore(today)) continue;
      byTournament.putIfAbsent(tid, () => {}).add(slotId);
    }
  }
  return {for (final e in byTournament.entries) e.key: e.value.length};
}
