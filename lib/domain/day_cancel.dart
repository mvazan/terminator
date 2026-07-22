/// "I'm playing here that day" cleanup: which of my availability ticks to
/// drop once a start of mine is fixed on [day].
library;

import 'models.dart';

/// Slot ids to untick: every slot of mine ticked on [day] (±1 day with
/// [includeNeighbors]) across ALL tournaments — except slots in [keep]
/// (the starts I'm actually rostered on; being signed up there stays true).
List<String> dayCancelTargets({
  required String uid,
  required Day day,
  required bool includeNeighbors,
  required List<Slot> slots,
  required List<Availability> availability,
  Set<String> keep = const {},
}) {
  final days = {
    day,
    if (includeNeighbors) ...{day.addDays(-1), day.addDays(1)},
  };
  final slotIdsOnDays = {
    for (final s in slots)
      if (days.contains(s.date)) s.id,
  };
  return [
    for (final a in availability)
      if (a.userId == uid &&
          slotIdsOnDays.contains(a.slotId) &&
          !keep.contains(a.slotId))
        a.slotId,
  ];
}
