/// "Committed elsewhere" — the single source of truth for who is already
/// playing on which day, and the interest-suppression derived from it.
///
/// A player is *committed* on day D when they hold a roster spot on a slot
/// that belongs to an ACTIVE order and that slot is dated D. Once committed,
/// their interest ticks that day are noise (Roman plays 18:00, so his 17:00/
/// 19:00/20:00 interest — same tournament OR another one — should vanish).
///
/// Everything here is pure/derived: nothing is written, so un-assigning a
/// player (or cancelling the order) restores their interest automatically.
library;

import 'models.dart';

/// One start a player is committed to play (an active-order roster entry).
class Commitment {
  const Commitment({
    required this.userId,
    required this.slotId,
    required this.day,
    required this.time,
    required this.tournamentId,
  });

  final String userId;
  final String slotId;
  final Day day;
  final HourMinute time;
  final String tournamentId;
}

/// Builds the commitment list from live data. [activeOrderSlotIds] = slot ids
/// covered by an order whose status is active (ordered/confirmed); guests
/// (roster entries with no userId) are skipped — they have no device/interest.
List<Commitment> buildCommitments({
  required List<RosterEntry> rosters,
  required Set<String> activeOrderSlotIds,
  required Map<String, Slot> slotsById,
}) {
  final out = <Commitment>[];
  for (final r in rosters) {
    final uid = r.userId;
    if (uid == null) continue;
    if (!activeOrderSlotIds.contains(r.slotId)) continue;
    final slot = slotsById[r.slotId];
    if (slot == null) continue;
    out.add(Commitment(
      userId: uid,
      slotId: r.slotId,
      day: slot.date,
      time: slot.time,
      tournamentId: slot.tournamentId,
    ));
  }
  return out;
}

/// userId → the set of days that user is committed to play.
Map<String, Set<Day>> committedDaysByUser(List<Commitment> commitments) {
  final map = <String, Set<Day>>{};
  for (final c in commitments) {
    map.putIfAbsent(c.userId, () => {}).add(c.day);
  }
  return map;
}

/// Drops every interest tick whose owner is committed on that tick's day —
/// the one filter reused by every team-interest display. [slotDayById] maps a
/// slot id to its day; a tick on an unknown slot is kept (can't judge it).
List<Availability> effectiveAvailability(
  List<Availability> availability,
  Map<String, Set<Day>> committedDays,
  Map<String, Day> slotDayById,
) {
  if (committedDays.isEmpty) return availability;
  return [
    for (final a in availability)
      if (!_isCommitted(a, committedDays, slotDayById)) a,
  ];
}

bool _isCommitted(
  Availability a,
  Map<String, Set<Day>> committedDays,
  Map<String, Day> slotDayById,
) {
  final days = committedDays[a.userId];
  if (days == null) return false;
  final day = slotDayById[a.slotId];
  return day != null && days.contains(day);
}

/// Commitments that clash with putting [userId] on a start dated [day] —
/// i.e. the player is already rostered on another active-order slot that day
/// (excluding [exceptSlotId], the start being added to). Feeds the ⚠️ dialog.
List<Commitment> conflictsFor(
  List<Commitment> commitments, {
  required String userId,
  required Day day,
  required String exceptSlotId,
}) {
  return [
    for (final c in commitments)
      if (c.userId == userId && c.day == day && c.slotId != exceptSlotId) c,
  ];
}
