import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/heatmap.dart';
import 'package:terminator/domain/models.dart';

import 'helpers.dart';

void main() {
  final thu = Day(2026, 4, 23);
  final fri = Day(2026, 4, 24);
  // "Today" before all slots so nothing counts as past in these cases.
  final beforeAll = Day(2026, 1, 1);
  final tournament = makeTournament(startsOn: thu, endsOn: fri, minPlayers: 2);

  final s1 = makeSlot('s1', thu, const HourMinute(18, 0));
  final s2 = makeSlot('s2', thu, const HourMinute(19, 0));
  final s3 = makeSlot('s3', fri, const HourMinute(18, 0));
  final slots = [s1, s2, s3];

  List<Availability> ticks(Map<String, List<String>> bySlot) => [
        for (final e in bySlot.entries)
          for (final user in e.value)
            Availability(slotId: e.key, userId: user),
      ];

  test('counts players per slot and flags orderable at min', () {
    final heatmap = Heatmap.build(
      tournament: tournament,
      slots: slots,
      availability: ticks({
        's1': ['u1', 'u2', 'u3'],
        's2': ['u1'],
      }),
    );

    expect(heatmap.bySlotId['s1']!.count, 3);
    expect(heatmap.bySlotId['s1']!.isOrderable, isTrue);
    expect(heatmap.bySlotId['s2']!.count, 1);
    expect(heatmap.bySlotId['s2']!.isOrderable, isFalse);
    expect(heatmap.bySlotId['s3']!.count, 0);
    expect(heatmap.maxCount, 3);
    expect(heatmap.intensity('s1'), 1.0);
    expect(heatmap.intensity('s3'), 0.0);
  });

  test('day stats aggregate distinct players across the day', () {
    final heatmap = Heatmap.build(
      tournament: tournament,
      slots: slots,
      availability: ticks({
        's1': ['u1', 'u2'],
        's2': ['u2', 'u3'],
        's3': ['u4'],
      }),
    );

    final thursday = heatmap.byDay[thu]!;
    expect(thursday.distinctPlayers, 3); // u1, u2, u3
    expect(heatmap.byDay[fri]!.distinctPlayers, 1);
  });

  test('empty availability yields zero intensity everywhere', () {
    final heatmap = Heatmap.build(
      tournament: tournament,
      slots: slots,
      availability: const [],
    );

    expect(heatmap.maxCount, 0);
    expect(heatmap.intensity('s1'), 0);
  });

  test('best picks rank by count, then earlier date and time', () {
    final heatmap = Heatmap.build(
      tournament: tournament,
      slots: slots,
      availability: ticks({
        's1': ['u1', 'u2'],
        's2': ['u1', 'u2'],
        's3': ['u1', 'u2', 'u3'],
      }),
    );

    final picks = bestPicks(heatmap: heatmap);
    expect(picks.map((p) => p.slot.id).toList(), ['s3', 's1', 's2']);
  });

  test('best picks exclude slots below minimum', () {
    final heatmap = Heatmap.build(
      tournament: tournament,
      slots: slots,
      availability: ticks({
        's1': ['u1'],
      }),
    );

    expect(bestPicks(heatmap: heatmap), isEmpty);
  });

  test('suggested bundle keeps only the strongest day, sorted by time', () {
    final heatmap = Heatmap.build(
      tournament: tournament,
      slots: slots,
      availability: ticks({
        's2': ['u1', 'u2', 'u3'],
        's1': ['u1', 'u2'],
        's3': ['u1', 'u2'],
      }),
    );

    final bundle = suggestedBundle(heatmap);
    expect(bundle.map((s) => s.slot.id).toList(), ['s1', 's2']);
  });

  group('interestByTournament', () {
    // Two tournaments: t1 has s1+s2 (thu) and s3 (fri); t2 has one slot.
    final s4 = makeSlot('s4', thu, const HourMinute(17, 0), tournamentId: 't2');

    test('distinct players, strongest day, and the mine flag per tournament',
        () {
      final interest = interestByTournament(
        slots: [...slots, s4],
        availability: ticks({
          's1': ['u1', 'u2'],
          's2': ['u2', 'u3'], // thu (s1+s2) = {u1,u2,u3} -> 3
          's3': ['u1'], //        fri = 1
          's4': ['u9'],
        }),
        today: beforeAll,
        endedTournamentIds: const {},
        uid: 'u1',
      );

      final t1 = interest['t1']!;
      expect(t1.players, 3);
      expect(t1.bestDayPlayers, 3);
      expect(t1.mine, isTrue);

      final t2 = interest['t2']!;
      expect(t2.players, 1);
      expect(t2.bestDayPlayers, 1);
      expect(t2.mine, isFalse);
    });

    test('venue-full slots count too — the grid shows them (may be ours)', () {
      final full = Slot(
        id: 'full',
        tournamentId: 't1',
        date: thu,
        time: const HourMinute(20, 0),
        venueCapacity: 4,
        venueOccupied: 4,
      );
      final interest = interestByTournament(
        slots: [full],
        availability: ticks({
          'full': ['u1'],
        }),
        today: beforeAll,
        endedTournamentIds: const {},
        uid: 'u1',
      );
      expect(interest['t1']!.players, 1);
    });

    test('no ticks -> tournament absent from the map', () {
      expect(
        interestByTournament(
            slots: slots,
            availability: const [],
            today: beforeAll,
            endedTournamentIds: const {},
            uid: 'u1'),
        isEmpty,
      );
    });
  });

  group('orderedSlotsByTournament', () {
    final s4 = makeSlot('s4', thu, const HourMinute(17, 0), tournamentId: 't2');
    final allSlots = [s1, s2, s3, s4]; // s1,s2,s3 -> t1; s4 -> t2

    test('counts distinct slots in active orders, per tournament', () {
      final ordered = orderedSlotsByTournament(
        slots: allSlots,
        orders: [
          makeOrder(id: 'o1', tournamentId: 't1'), // ordered (active)
          makeOrder(
              id: 'o2', tournamentId: 't2', status: OrderStatus.confirmed),
          makeOrder(
              id: 'o3', tournamentId: 't1', status: OrderStatus.proposed),
        ],
        orderSlots: {
          'o1': {'s1': 1, 's2': 1},
          'o2': {'s4': 2},
          'o3': {'s3': 1}, // proposal — must not count
        },
        today: beforeAll,
        endedTournamentIds: const {},
      );
      expect(ordered['t1'], 2);
      expect(ordered['t2'], 1);
    });

    test('no active orders -> empty', () {
      expect(
        orderedSlotsByTournament(
          slots: allSlots,
          orders: [
            makeOrder(id: 'o3', tournamentId: 't1', status: OrderStatus.proposed),
          ],
          orderSlots: {
            'o3': {'s1': 1},
          },
          today: beforeAll,
          endedTournamentIds: const {},
        ),
        isEmpty,
      );
    });
  });

  group('past days in summaries', () {
    // thu(23) has s1+s2, fri(24) has s3. "Today" = fri, so thu is past.
    final availability = ticks({
      's1': ['u1', 'u2', 'u3'], // thu (past) — 3 people
      's3': ['u1'], //             fri (today) — 1 person
    });

    test('running tournament drops its past days', () {
      final interest = interestByTournament(
        slots: slots,
        availability: availability,
        today: fri,
        endedTournamentIds: const {}, // t1 not ended
        uid: 'u1',
      );
      // Only fri counts: 1 player, best day 1.
      expect(interest['t1']!.players, 1);
      expect(interest['t1']!.bestDayPlayers, 1);
    });

    test('ended tournament keeps its whole history', () {
      final interest = interestByTournament(
        slots: slots,
        availability: availability,
        today: fri,
        endedTournamentIds: const {'t1'}, // t1 ended -> count everything
        uid: 'u1',
      );
      // Both days count: 3 distinct players, best day (thu) = 3.
      expect(interest['t1']!.players, 3);
      expect(interest['t1']!.bestDayPlayers, 3);
    });

    test('ordered count drops past slots for a running tournament', () {
      final ordered = orderedSlotsByTournament(
        slots: slots,
        orders: [makeOrder(id: 'o1', tournamentId: 't1')],
        orderSlots: {
          'o1': {'s1': 1, 's3': 1}, // s1 = thu (past), s3 = fri (today)
        },
        today: fri,
        endedTournamentIds: const {},
      );
      expect(ordered['t1'], 1); // only s3
    });
  });
}
