import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/domain/places.dart';

import 'helpers.dart';

void main() {
  final thu = Day(2026, 4, 23);
  // Default kind is dvojice → capacity 2 per start.
  final tournament = makeTournament(startsOn: thu, endsOn: thu);
  final s1 = makeSlot('s1', thu, const HourMinute(18, 0));
  final s2 = makeSlot('s2', thu, const HourMinute(19, 0));
  final s3 = makeSlot('s3', thu, const HourMinute(20, 0));

  RosterEntry member(String id, String slotId, String userId) =>
      RosterEntry(id: id, slotId: slotId, addedBy: 'u1', userId: userId);
  RosterEntry guest(String id, String slotId, String name) =>
      RosterEntry(id: id, slotId: slotId, addedBy: 'u1', guestName: name);

  test('the 5-players-order-6-lanes scenario', () {
    // 3 starts, 2 lanes each = 6 places; 5 members fill in, 1 stays free.
    final places = orderPlaces(
      tournament: tournament,
      orderSlots: [s1, s2, s3],
      lanesBySlot: {'s1': 2, 's2': 2, 's3': 2},
      rosters: [
        member('r1', 's1', 'u1'),
        member('r2', 's1', 'u2'),
        member('r3', 's2', 'u3'),
        member('r4', 's2', 'u4'),
        member('r5', 's3', 'u5'),
      ],
    );

    expect(places.orderedPlaces, 6);
    expect(places.filledPlaces, 5);
    expect(places.freePlaces, 1);
    expect(places.perSlot.last.hasFreePlace, isTrue);
    expect(places.perSlot.first.hasFreePlace, isFalse);
  });

  test('guests and repeat players fill places like anyone else', () {
    final places = orderPlaces(
      tournament: tournament,
      orderSlots: [s1, s2],
      lanesBySlot: {'s1': 2, 's2': 2},
      rosters: [
        member('r1', 's1', 'u1'),
        guest('r2', 's1', 'Franta bez appky'),
        member('r3', 's2', 'u1'), // u1 plays twice
      ],
    );

    expect(places.orderedPlaces, 4);
    expect(places.filledPlaces, 3);
    expect(places.freePlaces, 1);
  });

  test('slots are reported in date+time order', () {
    final places = orderPlaces(
      tournament: tournament,
      orderSlots: [s3, s1, s2],
      rosters: const [],
    );

    expect(places.perSlot.map((p) => p.slot.id).toList(), ['s1', 's2', 's3']);
  });

  test('ordered lanes per slot; one place per lane for non-tandem', () {
    // 4 lanes on s1, 1 lane (default) on s2; dvojice = 1 player per lane.
    final places = orderPlaces(
      tournament: tournament,
      orderSlots: [s1, s2],
      rosters: [
        member('r1', 's1', 'u1'),
        member('r2', 's1', 'u2'),
        member('r3', 's1', 'u3'),
      ],
      lanesBySlot: {'s1': 4, 's2': null},
    );

    expect(places.orderedLanes, 5); // 4 + default 1
    expect(places.orderedPlaces, 5); // 1 player per lane
    expect(places.filledPlaces, 3);
    expect(places.perSlot.first.lanes, 4);
    expect(places.perSlot.first.capacity, 4);
    expect(places.perSlot.first.hasFreePlace, isTrue);
    expect(places.perSlot.last.capacity, 1);
  });

  test('tandem: each ordered lane holds 2 players', () {
    final tandem = makeTournament(
      startsOn: thu,
      endsOn: thu,
      kind: TournamentKind.tandem,
    );
    // 2 lanes on s1 → 4 player places.
    final places = orderPlaces(
      tournament: tandem,
      orderSlots: [s1],
      rosters: [member('r1', 's1', 'u1'), member('r2', 's1', 'u2')],
      lanesBySlot: {'s1': 2},
    );

    expect(places.orderedLanes, 2);
    expect(places.orderedPlaces, 4); // 2 lanes × 2 players
    expect(places.filledPlaces, 2);
    expect(places.freePlaces, 2);
    expect(places.perSlot.single.hasFreePlace, isTrue);
  });

  test('one place per lane for a four-player kind (lanes, not team size)', () {
    final ctverice = makeTournament(
      startsOn: thu,
      endsOn: thu,
      kind: TournamentKind.ctverice,
    );
    // 4 lanes ordered → 4 places (čtveřice is still 1 player per lane).
    final places = orderPlaces(
      tournament: ctverice,
      orderSlots: [s1],
      rosters: [member('r1', 's1', 'u1')],
      lanesBySlot: {'s1': 4},
    );

    expect(places.orderedPlaces, 4);
    expect(places.freePlaces, 3);
    expect(places.perSlot.single.hasFreePlace, isTrue);
  });
}
