/// Slot-grid patterns: arbitrary groups of weekdays, each with its own start
/// times (replaces the fixed Mon–Fri / Sat–Sun split). A tournament can have
/// e.g. po+st+pá 16:00/17:30, út 18:00, so+ne 10:00/13:00.
library;

import 'models.dart';
import 'slot_generator.dart';

class DayGroup {
  DayGroup({Set<int>? weekdays, List<HourMinute>? times})
      : weekdays = weekdays ?? {},
        times = times ?? [];

  /// DateTime.monday (1) .. DateTime.sunday (7)
  final Set<int> weekdays;
  final List<HourMinute> times;

  bool get isComplete => weekdays.isNotEmpty && times.isNotEmpty;
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

/// Parses a free-text list of start times: "16 17:30, 19.00" →
/// [16:00, 17:30, 19:00]. Separators: comma, semicolon, whitespace.
/// Token formats: H, HH, H:MM, H.MM. Returns null when any token is invalid.
List<HourMinute>? parseTimesInput(String input) {
  final tokens = input
      .split(RegExp(r'[,;\s]+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return [];

  final times = <HourMinute>{};
  for (final token in tokens) {
    final match =
        RegExp(r'^(\d{1,2})(?:[:.](\d{1,2}))?$').firstMatch(token);
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minuteRaw = match.group(2);
    // "16.5" is ambiguous nonsense; minutes must be two digits when given.
    if (minuteRaw != null && minuteRaw.length != 2) return null;
    final minute = minuteRaw == null ? 0 : int.parse(minuteRaw);
    if (hour > 23 || minute > 59) return null;
    times.add(HourMinute(hour, minute));
  }
  return times.toList()..sort();
}
