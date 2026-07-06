/// Generates a tournament's start-slot grid from weekday/weekend time
/// patterns. Tournaments publish different start times Mon–Fri vs weekends
/// (e.g. 16:00/17:00/18:00 weekdays, 10:00/13:00 weekends).
library;

import 'models.dart';

class SlotSpec {
  const SlotSpec(this.date, this.time);

  final Day date;
  final HourMinute time;

  @override
  bool operator ==(Object other) =>
      other is SlotSpec && other.date == date && other.time == time;

  @override
  int get hashCode => Object.hash(date, time);

  @override
  String toString() => '$date $time';
}

/// One slot per (day in range) × (time in that day's pattern), sorted by
/// date then time. Days whose pattern is empty produce no slots.
List<SlotSpec> generateSlots({
  required Day startsOn,
  required Day endsOn,
  required List<HourMinute> weekdayTimes,
  required List<HourMinute> weekendTimes,
}) {
  if (endsOn.isBefore(startsOn)) return const [];

  final weekday = [...weekdayTimes]..sort();
  final weekend = [...weekendTimes]..sort();

  final specs = <SlotSpec>[];
  for (var d = startsOn; !d.isAfter(endsOn); d = d.addDays(1)) {
    for (final t in d.isWeekend ? weekend : weekday) {
      specs.add(SlotSpec(d, t));
    }
  }
  return specs;
}
