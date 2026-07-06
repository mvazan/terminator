/// Slot-grid patterns: arbitrary groups of weekdays, each with its own start
/// times (replaces the fixed Mon–Fri / Sat–Sun split). A tournament can have
/// e.g. po+st+pá 16:00/17:30, út 18:00, so+ne 10:00/13:00.
library;

import 'models.dart';

class DayGroup {
  DayGroup({Set<int>? weekdays, List<HourMinute>? times})
      : weekdays = weekdays ?? {},
        times = times ?? [];

  /// DateTime.monday (1) .. DateTime.sunday (7)
  final Set<int> weekdays;
  final List<HourMinute> times;
}

/// A single (date, time) slot specification produced by the generator.
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

/// One slot per date × (union of times of all groups covering that weekday).
/// Duplicate times across overlapping groups collapse into one slot.
List<SlotSpec> generateSlotsFromGroups({
  required Day startsOn,
  required Day endsOn,
  required List<DayGroup> groups,
}) {
  if (endsOn.isBefore(startsOn)) return const [];

  final specs = <SlotSpec>[];
  for (var d = startsOn; !d.isAfter(endsOn); d = d.addDays(1)) {
    final times = <HourMinute>{
      for (final g in groups)
        if (g.weekdays.contains(d.weekday)) ...g.times,
    }.toList()
      ..sort();
    for (final t in times) {
      specs.add(SlotSpec(d, t));
    }
  }
  return specs;
}
