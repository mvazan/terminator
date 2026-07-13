import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/domain/timeline.dart';

import 'helpers.dart';

void main() {
  test('weekStart returns Monday for any day of the week', () {
    final monday = Day(2026, 4, 20);
    expect(weekStart(monday), monday);
    expect(weekStart(Day(2026, 4, 23)), monday); // Thursday
    expect(weekStart(Day(2026, 4, 26)), monday); // Sunday
    expect(weekStart(Day(2026, 4, 27)), Day(2026, 4, 27)); // next Monday
  });

  test('builds columns spanning all tournaments and maps rows to columns', () {
    final vracov = makeTournament(
      id: 'a',
      venueId: 'v-vracov',
      startsOn: Day(2026, 4, 27),
      endsOn: Day(2026, 5, 10),
    );
    final olomouc = makeTournament(
      id: 'b',
      venueId: 'v-olomouc',
      kind: TournamentKind.tandem,
      startsOn: Day(2026, 5, 4),
      endsOn: Day(2026, 5, 31),
    );

    final timeline = Timeline.build([vracov, olomouc]);

    // Weeks of 27.4., 4.5., 11.5., 18.5., 25.5.
    expect(timeline.columns, hasLength(5));
    expect(timeline.columns.first.label(), '27.4.–3.5.');
    expect(timeline.columns.last.label(), '25.5.–31.5.');

    final rowA = timeline.rows[0];
    expect(rowA.startCol, 0);
    expect(rowA.endCol, 1);

    final rowB = timeline.rows[1];
    expect(rowB.startCol, 1);
    expect(rowB.endCol, 4);
    expect(rowB.tournament.timelineLabel('Olomouc'), 'Olomouc (tandem)');
  });

  test('single-week Fri–Sun tournament fills the right 3/7 of its cell', () {
    // 24.4.2026 is a Friday, 26.4. a Sunday — one week column.
    final t = makeTournament(
      id: 'a',
      venueId: 'v',
      startsOn: Day(2026, 4, 24),
      endsOn: Day(2026, 4, 26),
    );
    final row = Timeline.build([t]).rows.single;

    expect(row.startCol, 0);
    expect(row.endCol, 0);
    expect(row.startDay, 4); // Friday = index 4
    expect(row.endDay, 6); // Sunday = index 6
    // Fri..Sun inclusive = 3 of 7 days, inset 4/7 from the left.
    expect(row.fillFrom(0), closeTo(3 / 7, 1e-9));
    expect(row.insetAt(0), closeTo(4 / 7, 1e-9));
    expect(row.fillFrom(1), 0); // outside the span
  });

  test('multi-week bar: partial ends, full middle weeks', () {
    // Wed 22.4. → Tue 5.5.2026. Week0 Wed–Sun, week1 full, week2 Mon–Tue.
    final t = makeTournament(
      id: 'a',
      venueId: 'v',
      startsOn: Day(2026, 4, 22), // Wednesday = index 2
      endsOn: Day(2026, 5, 5), // Tuesday = index 1
    );
    final row = Timeline.build([t]).rows.single;

    expect(row.startCol, 0);
    expect(row.endCol, 2);
    // Start cell: Wed..Sun = 5/7, inset 2/7.
    expect(row.fillFrom(0), closeTo(5 / 7, 1e-9));
    expect(row.insetAt(0), closeTo(2 / 7, 1e-9));
    // Middle cell: full week.
    expect(row.fillFrom(1), 1.0);
    expect(row.insetAt(1), 0);
    // End cell: Mon..Tue = 2/7, no inset.
    expect(row.fillFrom(2), closeTo(2 / 7, 1e-9));
    expect(row.insetAt(2), 0);
  });

  test('empty input produces an empty timeline', () {
    final timeline = Timeline.build(const []);
    expect(timeline.isEmpty, isTrue);
    expect(timeline.columns, isEmpty);
  });

  group('day markers', () {
    test('land in the right column and day index across week boundaries', () {
      // Wed 22.4. → Tue 5.5.2026 spans three week columns.
      final t = makeTournament(
        id: 'a',
        venueId: 'v',
        startsOn: Day(2026, 4, 22),
        endsOn: Day(2026, 5, 5),
      );
      final row = Timeline.build([
        t
      ], tickedDaysByTournament: {
        'a': {Day(2026, 4, 24), Day(2026, 5, 4)}, // Fri wk0, Mon wk2 (my ticks)
      }).rows.single;

      expect(row.markers, hasLength(2));
      final friday = row.markersIn(0).single;
      expect(friday.dayIndex, 4);
      expect(friday.kind, DayMarkerKind.tick);
      final monday = row.markersIn(2).single;
      expect(monday.dayIndex, 0);
      expect(row.markersIn(1), isEmpty);
    });

    test('an ordered day overrides its tick marker', () {
      final t = makeTournament(
        id: 'a',
        venueId: 'v',
        startsOn: Day(2026, 4, 20),
        endsOn: Day(2026, 4, 26),
      );
      final row = Timeline.build([
        t
      ], tickedDaysByTournament: {
        'a': {Day(2026, 4, 23)},
      }, orderedDaysByTournament: {
        'a': {Day(2026, 4, 23)},
      }).rows.single;

      expect(row.markers.single.kind, DayMarkerKind.ordered);
    });

    test('no marker maps -> empty markers, old call sites keep working', () {
      final t = makeTournament(
        id: 'a',
        venueId: 'v',
        startsOn: Day(2026, 4, 20),
        endsOn: Day(2026, 4, 26),
      );
      expect(Timeline.build([t]).rows.single.markers, isEmpty);
    });
  });
}
