/// Colored-map logic: pick one representative tournament per venue and grade
/// its pin by the current user's personal state. Pure so it can be unit-tested
/// without a map or providers.
library;

import 'models.dart';

/// Pin buckets, from a personal point of view. Greys ignore signup; green =
/// running, orange = upcoming, and the shade deepens with my involvement
/// (none -> I ticked -> I'm on an ordered start).
enum VenuePinState {
  hidden, // I hid this tournament ("nezajímá mě") — light grey
  past, // already over — dark grey
  ongoingNone, // running, I'm not signed up — light green
  ongoingMine, // running, I ticked — mid green
  ongoingStart, // running, I'm on an ordered start — dark green
  upcomingNone, // upcoming, I'm not signed up — light orange
  upcomingMine, // upcoming, I ticked — mid orange
  upcomingStart, // upcoming, I'm on an ordered start — dark orange
}

/// The one tournament that represents a venue on the colored map, plus its pin
/// state. Priority: a running tournament, else the nearest upcoming, else the
/// most recent past. Returns null when the venue has no tournament to show.
({Tournament tournament, VenuePinState state})? venuePin({
  required List<Tournament> venueTournaments,
  required Day today,
  required Set<String> hiddenByMe,
  required Set<String> myTicked,
  required Set<String> myStart,
}) {
  if (venueTournaments.isEmpty) return null;

  bool isOngoing(Tournament t) =>
      !t.startsOn.isAfter(today) && !t.endsOn.isBefore(today);

  final ongoing = venueTournaments.where(isOngoing).toList()
    ..sort((a, b) => a.endsOn.compareTo(b.endsOn)); // ending soonest first
  final upcoming = venueTournaments.where((t) => t.startsOn.isAfter(today))
      .toList()
    ..sort((a, b) => a.startsOn.compareTo(b.startsOn)); // nearest first
  final past = venueTournaments.where((t) => t.endsOn.isBefore(today)).toList()
    ..sort((a, b) => b.endsOn.compareTo(a.endsOn)); // most recent first

  final t = ongoing.isNotEmpty
      ? ongoing.first
      : upcoming.isNotEmpty
          ? upcoming.first
          : past.first;

  return (tournament: t, state: _stateFor(t, today, hiddenByMe, myTicked, myStart));
}

VenuePinState _stateFor(Tournament t, Day today, Set<String> hiddenByMe,
    Set<String> myTicked, Set<String> myStart) {
  if (hiddenByMe.contains(t.id)) return VenuePinState.hidden;
  if (t.endsOn.isBefore(today)) return VenuePinState.past;
  final ongoing = !t.startsOn.isAfter(today);
  if (myStart.contains(t.id)) {
    return ongoing ? VenuePinState.ongoingStart : VenuePinState.upcomingStart;
  }
  if (myTicked.contains(t.id)) {
    return ongoing ? VenuePinState.ongoingMine : VenuePinState.upcomingMine;
  }
  return ongoing ? VenuePinState.ongoingNone : VenuePinState.upcomingNone;
}
