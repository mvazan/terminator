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

/// A vertical day mark inside a tournament's bar: the tournament has starts
/// (slots) on that day, or — stronger — an active order there.
enum DayMarkerKind { start, ordered }

class DayMarker {
  const DayMarker({
    required this.col,
    required this.dayIndex,
    required this.kind,
  });

  /// Column index into [Timeline.columns].
  final int col;

  /// 0 = Monday … 6 = Sunday within that week.
  final int dayIndex;
  final DayMarkerKind kind;
}

class TimelineRow {
  const TimelineRow({
    required this.tournament,
    required this.startCol,
    required this.endCol,
    required this.startDay,
    required this.endDay,
    this.markers = const [],
  });

  final Tournament tournament;

  /// Day marks (starts/orders) for this tournament, precomputed per column.
  final List<DayMarker> markers;

  /// Markers falling into [col] — lists are tiny, a linear filter is fine.
  List<DayMarker> markersIn(int col) =>
      [for (final m in markers) if (m.col == col) m];

  /// Inclusive column indexes into [Timeline.columns].
  final int startCol;
  final int endCol;

  /// Day-of-week offset (0 = Monday … 6 = Sunday) of the tournament's first day
  /// within [startCol], and of its last day within [endCol]. Lets the timeline
  /// fill only part of a boundary week's cell (a Fri–Sun tournament fills the
  /// right 3/7 of its single week cell).
  final int startDay;
  final int endDay;

  /// Fraction (0..1) of [col]'s cell that the bar covers. Full weeks → 1.0;
  /// the start cell is filled from [startDay] rightward, the end cell up to and
  /// including [endDay]. A single-week tournament intersects both trims.
  double fillFrom(int col) {
    if (col < startCol || col > endCol) return 0;
    final from = col == startCol ? startDay : 0;
    final to = col == endCol ? endDay : 6;
    return (to - from + 1) / 7;
  }

  /// Left inset fraction (0..1) for [col] — the start cell begins at [startDay].
  double insetAt(int col) => col == startCol ? startDay / 7 : 0;
}

class Timeline {
  const Timeline({required this.columns, required this.rows});

  final List<WeekColumn> columns;
  final List<TimelineRow> rows;

  bool get isEmpty => rows.isEmpty;

  /// Builds the timeline covering every week any tournament touches.
  /// Rows keep the given tournament order (caller sorts, typically by start).
  ///
  /// [startDaysByTournament] / [orderedDaysByTournament] mark days that have
  /// starts (slots) resp. an active order — rendered as vertical lines in the
  /// bar. A day that is both start and ordered renders as ordered.
  factory Timeline.build(
    List<Tournament> tournaments, {
    Map<String, Set<Day>> startDaysByTournament = const {},
    Map<String, Set<Day>> orderedDaysByTournament = const {},
  }) {
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

    List<DayMarker> markersOf(Tournament t) {
      final ordered = orderedDaysByTournament[t.id] ?? const <Day>{};
      final starts = startDaysByTournament[t.id] ?? const <Day>{};
      return [
        for (final d in {...starts, ...ordered})
          DayMarker(
            col: colOf(d),
            dayIndex: d.weekday - 1,
            kind: ordered.contains(d)
                ? DayMarkerKind.ordered
                : DayMarkerKind.start,
          ),
      ];
    }

    final rows = [
      for (final t in tournaments)
        TimelineRow(
          tournament: t,
          startCol: colOf(t.startsOn),
          endCol: colOf(t.endsOn),
          startDay: t.startsOn.weekday - 1,
          endDay: t.endsOn.weekday - 1,
          markers: markersOf(t),
        ),
    ];

    return Timeline(columns: columns, rows: rows);
  }
}
