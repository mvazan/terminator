import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/domain/open_spots.dart';

import 'helpers.dart';

void main() {
  final today = Day(2026, 9, 1);
  final sat = Day(2026, 9, 5);
  // Default kind is dvojice → 2 places per lane-start.
  final tournament = makeTournament(startsOn: sat, endsOn: sat);
  final s1 = makeSlot('s1', sat, const HourMinute(17, 0));
  final s2 = makeSlot('s2', sat, const HourMinute(19, 0));

  RosterEntry member(String id, String slotId, String userId) =>
      RosterEntry(id: id, slotId: slotId, addedBy: 'u1', userId: userId);

  // Capacity/guest/tandem math itself is orderPlaces' contract — covered by
  // places_test.dart; here we test the cross-tournament selection.
  List<OpenSpot> run({
    List<Order>? orders,
    Map<String, Map<String, int>>? orderSlots,
    Map<String, Slot>? slotById,
    Map<String, Tournament>? tournamentById,
    List<RosterEntry> rosters = const [],
    Day? now,
  }) =>
      openSpots(
        orders: orders ?? [makeOrder()],
        orderSlots: orderSlots ??
            {
              'o1': {'s1': 2, 's2': 2},
            },
        slotById: slotById ?? {'s1': s1, 's2': s2},
        tournamentById: tournamentById ?? {'t1': tournament},
        rosters: rosters,
        today: now ?? today,
      );

  test('active order with a free place shows up once, joined + counted', () {
    // 2 starts × 2 lanes (dvojice = 1 player/lane) = 4 places; 3 rostered
    // → 1 free.
    final spots = run(rosters: [
      member('r1', 's1', 'u1'),
      member('r2', 's1', 'u2'),
      member('r3', 's2', 'u3'),
    ]);
    expect(spots, hasLength(1));
    expect(spots.single.order.id, 'o1');
    expect(spots.single.tournament.id, 't1');
    expect(spots.single.freePlaces, 1);
    expect(spots.single.firstFree.id, 's2'); // s1 is full (2/2)
  });

  test('full order is excluded', () {
    final spots = run(rosters: [
      member('r1', 's1', 'u1'),
      member('r2', 's1', 'u2'),
      member('r3', 's2', 'u3'),
      member('r4', 's2', 'u4'),
    ]);
    expect(spots, isEmpty);
  });

  test('proposals and cancelled orders are excluded', () {
    for (final status in [OrderStatus.proposed, OrderStatus.cancelled]) {
      expect(run(orders: [makeOrder(status: status)]), isEmpty);
    }
  });

  test('venue-cancelled slot counts neither capacity nor roster', () {
    final cancelled = makeSlot('s1', sat, const HourMinute(17, 0),
        cancelledAt: DateTime.utc(2026, 8, 30));
    // Free capacity only on the cancelled slot → nothing joinable.
    final spots = run(
      slotById: {'s1': cancelled, 's2': s2},
      rosters: [member('r1', 's2', 'u1'), member('r2', 's2', 'u2')],
    );
    expect(spots, isEmpty);
    // Cancelled slot between joinable ones: its roster rows don't leak
    // into the count, its capacity doesn't inflate freePlaces.
    final spots2 = run(
      slotById: {'s1': cancelled, 's2': s2},
      rosters: [member('r1', 's1', 'u1')],
    );
    expect(spots2.single.freePlaces, 2); // only s2's 2 lanes count
    expect(spots2.single.firstFree.id, 's2');
  });

  test('past days are excluded; today itself still counts', () {
    final past = makeSlot('s1', Day(2026, 8, 28), const HourMinute(17, 0));
    expect(run(slotById: {'s1': past, 's2': past}), isEmpty);

    final todaySlot = makeSlot('s1', today, const HourMinute(17, 0));
    final spots = run(
      orderSlots: {
        'o1': {'s1': 1},
      },
      slotById: {'s1': todaySlot},
    );
    expect(spots.single.firstFree.id, 's1');
  });

  test('hidden (absent from map) and archived tournaments are excluded', () {
    expect(run(tournamentById: {}), isEmpty);
    final archived = makeTournament(
        startsOn: sat, endsOn: sat, archivedAt: DateTime.utc(2026, 8, 1));
    expect(run(tournamentById: {'t1': archived}), isEmpty);
  });

  test('slot id missing from slotById is skipped without throwing', () {
    final spots = run(
      orderSlots: {
        'o1': {'ghost': 2, 's2': 1},
      },
    );
    expect(spots.single.freePlaces, 1); // only s2's single lane counts
  });

  test('rows sort by first free start, deterministic tie-break', () {
    final sun = Day(2026, 9, 6);
    final tShort = makeTournament(id: 'tA', name: 'A', startsOn: sat, endsOn: sun);
    final tLong = makeTournament(id: 'tB', name: 'B', startsOn: sat, endsOn: sun);
    final early = makeSlot('e', sat, const HourMinute(10, 0), tournamentId: 'tB');
    final late = makeSlot('l', sun, const HourMinute(10, 0), tournamentId: 'tA');
    final spots = run(
      orders: [
        makeOrder(id: 'oA', tournamentId: 'tA'),
        makeOrder(id: 'oB', tournamentId: 'tB'),
      ],
      orderSlots: {
        'oA': {'l': 1},
        'oB': {'e': 1},
      },
      slotById: {'e': early, 'l': late},
      tournamentById: {'tA': tShort, 'tB': tLong},
    );
    expect([for (final s in spots) s.order.id], ['oB', 'oA']);
  });
}
