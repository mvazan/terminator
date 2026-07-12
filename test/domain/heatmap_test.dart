import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/heatmap.dart';
import 'package:terminator/domain/models.dart';

import 'helpers.dart';

void main() {
  final thu = Day(2026, 4, 23);
  final fri = Day(2026, 4, 24);
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

    test('venue-full slots are excluded, matching the detail grid', () {
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
        uid: 'u1',
      );
      expect(interest, isEmpty);
    });

    test('no ticks -> tournament absent from the map', () {
      expect(
        interestByTournament(slots: slots, availability: const [], uid: 'u1'),
        isEmpty,
      );
    });
  });
}
