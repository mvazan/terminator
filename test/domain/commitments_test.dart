import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/commitments.dart';
import 'package:terminator/domain/models.dart';

import 'helpers.dart';

void main() {
  final d = Day(2026, 8, 26);
  final other = Day(2026, 8, 27);

  // Vracov (t1): Roman's ordered start 18:00 + free-interest starts.
  final s17 = makeSlot('s17', d, const HourMinute(17, 0));
  final s18 = makeSlot('s18', d, const HourMinute(18, 0));
  final s19 = makeSlot('s19', d, const HourMinute(19, 0));
  // Bratislava (t2): another tournament, same day.
  final b16 = makeSlot('b16', d, const HourMinute(16, 0), tournamentId: 't2');
  // Next day, Vracov.
  final s10 = makeSlot('s10', other, const HourMinute(10, 0));

  final slotsById = {
    for (final s in [s17, s18, s19, b16, s10]) s.id: s,
  };
  final slotDay = {for (final s in slotsById.values) s.id: s.date};

  RosterEntry roster(String id, String slotId, {String? user = 'roman'}) =>
      RosterEntry(id: id, slotId: slotId, addedBy: 'u1', userId: user);

  group('buildCommitments', () {
    test('roster on an active-order slot becomes a commitment', () {
      final c = buildCommitments(
        rosters: [roster('r1', 's18')],
        activeOrderSlotIds: {'s18'},
        slotsById: slotsById,
      );
      expect(c, hasLength(1));
      expect(c.single.userId, 'roman');
      expect(c.single.day, d);
      expect(c.single.tournamentId, 't1');
    });

    test('roster on a slot NOT in an active order is ignored', () {
      final c = buildCommitments(
        rosters: [roster('r1', 's18')],
        activeOrderSlotIds: const {}, // order cancelled / not active
        slotsById: slotsById,
      );
      expect(c, isEmpty);
    });

    test('guests (no userId) are skipped', () {
      final c = buildCommitments(
        rosters: [RosterEntry(id: 'g', slotId: 's18', addedBy: 'u1',
            userId: null, guestName: 'Franta')],
        activeOrderSlotIds: {'s18'},
        slotsById: slotsById,
      );
      expect(c, isEmpty);
    });
  });

  group('effectiveAvailability', () {
    // Roman is committed at 18:00; his other interest that day is noise.
    final committed = committedDaysByUser(buildCommitments(
      rosters: [roster('r1', 's18')],
      activeOrderSlotIds: {'s18'},
      slotsById: slotsById,
    ));

    test('Roman case: same-day, same-tournament interest suppressed', () {
      final avail = [
        const Availability(slotId: 's17', userId: 'roman'),
        const Availability(slotId: 's19', userId: 'roman'),
        const Availability(slotId: 's17', userId: 'pavel'), // not committed
      ];
      final eff = effectiveAvailability(avail, committed, slotDay);
      expect(eff.map((a) => '${a.slotId}:${a.userId}'),
          ['s17:pavel']); // both Roman ticks gone, Pavel stays
    });

    test('Blansko/Bratislava: committed in t2 suppresses interest in t1', () {
      // Roman committed in Bratislava (t2) 16:00; his Vracov (t1) interest
      // that day vanishes — Blansko no longer looks like he can play.
      final committedElsewhere = committedDaysByUser(buildCommitments(
        rosters: [roster('r1', 'b16')],
        activeOrderSlotIds: {'b16'},
        slotsById: slotsById,
      ));
      final avail = [
        const Availability(slotId: 's17', userId: 'roman'), // t1, same day
      ];
      expect(effectiveAvailability(avail, committedElsewhere, slotDay),
          isEmpty);
    });

    test('other days keep their interest', () {
      final avail = [
        const Availability(slotId: 's10', userId: 'roman'), // next day
      ];
      expect(effectiveAvailability(avail, committed, slotDay), hasLength(1));
    });

    test('restore: no commitments -> availability untouched', () {
      final avail = [const Availability(slotId: 's17', userId: 'roman')];
      expect(effectiveAvailability(avail, const {}, slotDay), avail);
    });
  });

  group('conflictsFor', () {
    final commitments = buildCommitments(
      rosters: [roster('r1', 'b16')], // Roman already in Bratislava that day
      activeOrderSlotIds: {'b16'},
      slotsById: slotsById,
    );

    test('adding Roman to another start the same day flags the conflict', () {
      final conflicts = conflictsFor(commitments,
          userId: 'roman', day: d, exceptSlotId: 's18');
      expect(conflicts, hasLength(1));
      expect(conflicts.single.slotId, 'b16');
      expect(conflicts.single.time, const HourMinute(16, 0));
    });

    test('the same slot is not a conflict with itself', () {
      expect(
          conflictsFor(commitments,
              userId: 'roman', day: d, exceptSlotId: 'b16'),
          isEmpty);
    });

    test('a different day is not a conflict', () {
      expect(
          conflictsFor(commitments,
              userId: 'roman', day: other, exceptSlotId: 's18'),
          isEmpty);
    });

    test('a different user is not a conflict', () {
      expect(
          conflictsFor(commitments,
              userId: 'pavel', day: d, exceptSlotId: 's18'),
          isEmpty);
    });
  });

  group('myUpcomingStarts (Moje starty)', () {
    final t1 = makeTournament(startsOn: d, endsOn: other);
    final tournamentsById = {'t1': t1};

    // The exact bug from the field: Radek cancelled Thursday's order and
    // re-made it for Wednesday. Roster rows on the Thursday slot survive the
    // cancellation (by design), so a raw-roster listing showed both days.
    test('a start whose order was cancelled disappears', () {
      final commitments = buildCommitments(
        rosters: [roster('r1', 's18'), roster('r2', 's10')],
        // Only s18 (Wednesday) is still covered by an active order; the
        // cancelled Thursday order left s10 uncovered.
        activeOrderSlotIds: {'s18'},
        slotsById: slotsById,
      );
      final mine = myUpcomingStarts(
        commitments,
        userId: 'roman',
        today: d,
        slotById: slotsById,
        tournamentById: tournamentsById,
      );
      expect(mine, hasLength(1));
      expect(mine.single.slot.id, 's18');
    });

    test('only my own starts, future only, sorted by date then time', () {
      final commitments = buildCommitments(
        rosters: [
          roster('r1', 's10'),               // future (27.8.)
          roster('r2', 's18'),               // today (26.8.) — stays
          roster('r3', 's17', user: 'jana'), // someone else's
        ],
        activeOrderSlotIds: {'s10', 's18', 's17'},
        slotsById: slotsById,
      );
      final mine = myUpcomingStarts(
        commitments,
        userId: 'roman',
        today: d,
        slotById: slotsById,
        tournamentById: tournamentsById,
      );
      expect([for (final m in mine) m.slot.id], ['s18', 's10']);
    });

    test('a start in the past is gone', () {
      final commitments = buildCommitments(
        rosters: [roster('r1', 's18')],
        activeOrderSlotIds: {'s18'},
        slotsById: slotsById,
      );
      final mine = myUpcomingStarts(
        commitments,
        userId: 'roman',
        today: other, // s18 is dated d = the day before
        slotById: slotsById,
        tournamentById: tournamentsById,
      );
      expect(mine, isEmpty);
    });
  });
}
