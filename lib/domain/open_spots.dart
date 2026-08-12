/// The home screen's "Volná místa" noticeboard: every active order, across
/// all visible tournaments, that still has a free place on an upcoming
/// start — so finding where to join doesn't mean combing tournament details.
///
/// Counts only joinable starts: venue-cancelled slots (cancelled_at) and
/// past days are out of both capacity and filled (the roster association
/// goes through the order's slot ids, matching OrderCard's math including
/// its ghost-roster quirk — counts here and there always agree).
library;

import 'models.dart';
import 'places.dart';

/// One joinable order: where, when the first free start is, how many places.
typedef OpenSpot = ({
  Order order,
  Tournament tournament,
  Slot firstFree,
  int freePlaces,
});

/// Cross-tournament pick of active orders with a free place on an upcoming
/// start, sorted by that start. [tournamentById] must come from the VISIBLE
/// tournament list — hidden tournaments are excluded simply by being absent.
List<OpenSpot> openSpots({
  required List<Order> orders,
  required Map<String, Map<String, int>> orderSlots, // order → slot → lanes
  required Map<String, Slot> slotById,
  required Map<String, Tournament> tournamentById,
  required List<RosterEntry> rosters,
  required Day today,
}) {
  final spots = <OpenSpot>[];
  for (final order in orders) {
    if (!order.isActive) continue;
    final tournament = tournamentById[order.tournamentId];
    if (tournament == null || tournament.isArchived) continue;
    final lanesBySlot = orderSlots[order.id];
    if (lanesBySlot == null || lanesBySlot.isEmpty) continue;

    // Only joinable starts feed orderPlaces: restricting the slot list
    // restricts both capacity and filled to them.
    final joinable = [
      for (final id in lanesBySlot.keys)
        if (slotById[id] case final Slot s
            when !s.cancelled && !s.date.isBefore(today))
          s,
    ];
    if (joinable.isEmpty) continue;

    final places = orderPlaces(
      tournament: tournament,
      orderSlots: joinable,
      rosters: rosters,
      lanesBySlot: lanesBySlot,
    );
    if (places.freePlaces <= 0) continue;

    // The first start someone can actually join — a full 17:00 before a
    // free 19:00 would mislead the person about to tap.
    final firstFree =
        places.perSlot.firstWhere((p) => p.hasFreePlace).slot;
    spots.add((
      order: order,
      tournament: tournament,
      firstFree: firstFree,
      freePlaces: places.freePlaces,
    ));
  }
  spots.sort((a, b) {
    final byStart = Slot.compare(a.firstFree, b.firstFree);
    if (byStart != 0) return byStart;
    final byName = a.tournament.name.compareTo(b.tournament.name);
    if (byName != 0) return byName;
    return a.order.id.compareTo(b.order.id); // deterministic (sort unstable)
  });
  return spots;
}
