/// Week bucketing for the season timeline — the Gantt view that mirrors the
/// team's spreadsheet: rows = tournaments, columns = weeks, bars = duration.
library;

import 'models.dart';

/// Monday of the week containing [day].
Day weekStart(Day day) => day.addDays(1 - day.weekday);

/// One column of the timeline: the week starting [monday] (inclusive) through
/// the following Sunday.
class WeekColumn {
  const WeekColumn(this.monday);

  final Day monday;

  Day get sunday => monday.addDays(6);

  /// "20.4.–26.4." — the header label used in the team's spreadsheet.
  String label() =>
      '${monday.day}.${monday.month}.–${sunday.day}.${sunday.month}.';
}

class TimelineRow {
  const TimelineRow({
    required this.tournament,
    required this.startCol,
    required this.endCol,
  });

  final Tournament tournament;

  /// Inclusive column indexes into [Timeline.columns].
  final int startCol;
  final int endCol;
}

class Timeline {
  const Timeline({required this.columns, required this.rows});

  final List<WeekColumn> columns;
  final List<TimelineRow> rows;

  bool get isEmpty => rows.isEmpty;

  /// Builds the timeline covering every week any tournament touches.
  /// Rows keep the given tournament order (caller sorts, typically by start).
  factory Timeline.build(List<Tournament> tournaments) {
    if (tournaments.isEmpty) {
      return const Timeline(columns: [], rows: []);
    }

    var first = weekStart(tournaments.first.startsOn);
    var lastStart = weekStart(tournaments.first.endsOn);
    for (final t in tournaments) {
      final s = weekStart(t.startsOn);
      final e = weekStart(t.endsOn);
      if (s.isBefore(first)) first = s;
      if (e.isAfter(lastStart)) lastStart = e;
    }

    final columns = <WeekColumn>[];
    for (var m = first; !m.isAfter(lastStart); m = m.addDays(7)) {
      columns.add(WeekColumn(m));
    }

    int colOf(Day day) => weekStart(day).differenceInDays(first) ~/ 7;

    final rows = [
      for (final t in tournaments)
        TimelineRow(
          tournament: t,
          startCol: colOf(t.startsOn),
          endCol: colOf(t.endsOn),
        ),
    ];

    return Timeline(columns: columns, rows: rows);
  }
}
