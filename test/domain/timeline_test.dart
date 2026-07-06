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
      venue: 'Vracov',
      startsOn: Day(2026, 4, 27),
      endsOn: Day(2026, 5, 10),
    );
    final olomouc = makeTournament(
      id: 'b',
      venue: 'Olomouc',
      kind: 'tandemy',
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
    expect(rowB.tournament.timelineLabel, 'Olomouc (tandemy)');
  });

  test('empty input produces an empty timeline', () {
    final timeline = Timeline.build(const []);
    expect(timeline.isEmpty, isTrue);
    expect(timeline.columns, isEmpty);
  });
}
