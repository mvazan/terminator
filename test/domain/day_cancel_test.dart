import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/day_cancel.dart';
import 'package:terminator/domain/models.dart';

import 'helpers.dart';

void main() {
  final fri = Day(2026, 8, 21);
  final sat = Day(2026, 8, 22);
  final sun = Day(2026, 8, 23);

  // Saturday: my start (s1, kept) + another tournament (s2). Friday s3,
  // Sunday s4, plus a Saturday slot ticked by someone else (s2/u2).
  final slots = [
    makeSlot('s1', sat, const HourMinute(17, 30)),
    makeSlot('s2', sat, const HourMinute(10, 0), tournamentId: 't2'),
    makeSlot('s3', fri, const HourMinute(18, 0), tournamentId: 't3'),
    makeSlot('s4', sun, const HourMinute(9, 0), tournamentId: 't4'),
  ];
  final availability = [
    const Availability(slotId: 's1', userId: 'me'),
    const Availability(slotId: 's2', userId: 'me'),
    const Availability(slotId: 's2', userId: 'u2'),
    const Availability(slotId: 's3', userId: 'me'),
    const Availability(slotId: 's4', userId: 'me'),
  ];

  test('same day only: drops other tournaments, keeps my rostered start', () {
    final targets = dayCancelTargets(
      uid: 'me',
      day: sat,
      includeNeighbors: false,
      slots: slots,
      availability: availability,
      keep: {'s1'},
    );
    expect(targets, ['s2']); // not s1 (rostered), not u2's tick, not fri/sun
  });

  test('with neighbors: friday and sunday ticks go too', () {
    final targets = dayCancelTargets(
      uid: 'me',
      day: sat,
      includeNeighbors: true,
      slots: slots,
      availability: availability,
      keep: {'s1'},
    );
    expect(targets.toSet(), {'s2', 's3', 's4'});
  });

  test('nothing to cancel -> empty', () {
    final targets = dayCancelTargets(
      uid: 'me',
      day: Day(2026, 12, 24),
      includeNeighbors: true,
      slots: slots,
      availability: availability,
    );
    expect(targets, isEmpty);
  });
}
