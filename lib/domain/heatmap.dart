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
