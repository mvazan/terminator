/// Per-person summaries of ticked start times — "who's in" under each day of
/// the detail grid reads `Pavel: celý den · Miloš: od 17:00` instead of one
/// line per slot.
library;

import 'heatmap.dart';
import 'models.dart';

/// Summarizes one person's ticks against a day's start times.
///
/// [dayTimes]: all of the day's slot times, sorted ascending, distinct.
/// Rules (checked in order):
///  - every slot ticked             -> 'celý den'
///  - exactly one tick              -> '15:00'
///  - contiguous run to the end     -> 'od 15:00' (first ticked time)
///  - contiguous run from the start -> 'do 15:00' (LAST ticked time — these
///    are start times, not an interval, so "starts up to and incl. 15:00")
///  - contiguous middle run         -> '12:00–15:00'
///  - non-contiguous                -> '12:00, 15:00, 19:00'
String summarizeTimes(List<HourMinute> dayTimes, Set<HourMinute> ticked) {
  final indexes = [
    for (var i = 0; i < dayTimes.length; i++)
      if (ticked.contains(dayTimes[i])) i,
  ];
  if (indexes.isEmpty) return '';
  if (indexes.length == dayTimes.length) return 'celý den';
  if (indexes.length == 1) return dayTimes[indexes.single].display();

  var contiguous = true;
  for (var i = 1; i < indexes.length; i++) {
    if (indexes[i] != indexes[i - 1] + 1) {
      contiguous = false;
      break;
    }
  }
  final first = dayTimes[indexes.first];
  final last = dayTimes[indexes.last];
  if (!contiguous) {
    return [for (final i in indexes) dayTimes[i].display()].join(', ');
  }
  if (indexes.last == dayTimes.length - 1) return 'od ${first.display()}';
  if (indexes.first == 0) return 'do ${last.display()}';
  return '${first.display()}–${last.display()}';
}

/// Per-person summaries for one day: userId -> [summarizeTimes] label.
/// Only users with at least one tick appear; the caller sorts by name.
Map<String, String> summarizeDayByUser({
  required List<Slot> daySlots,
  required Map<String, SlotStats> statsBySlotId,
}) {
  final dayTimes = [for (final s in daySlots) s.time]..sort();
  final tickedByUser = <String, Set<HourMinute>>{};
  for (final slot in daySlots) {
    for (final userId
        in statsBySlotId[slot.id]?.userIds ?? const <String>{}) {
      tickedByUser.putIfAbsent(userId, () => {}).add(slot.time);
    }
  }
  return {
    for (final e in tickedByUser.entries)
      e.key: summarizeTimes(dayTimes, e.value),
  };
}
