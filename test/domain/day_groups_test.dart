import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/day_groups.dart';
import 'package:terminator/domain/models.dart';

void main() {
  // 2026-04-20 Mon .. 2026-04-26 Sun
  final monday = Day(2026, 4, 20);
  final sunday = Day(2026, 4, 26);

  group('generateSlotsFromGroups', () {
    test('arbitrary day groups: po+st+pá / út / weekend', () {
      final slots = generateSlotsFromGroups(
        startsOn: monday,
        endsOn: sunday,
        groups: [
          DayGroup(
            weekdays: {DateTime.monday, DateTime.wednesday, DateTime.friday},
            times: [const HourMinute(16, 0), const HourMinute(17, 30)],
          ),
          DayGroup(
            weekdays: {DateTime.tuesday},
            times: [const HourMinute(18, 0)],
          ),
          DayGroup(
            weekdays: {DateTime.saturday, DateTime.sunday},
            times: [const HourMinute(10, 0)],
          ),
        ],
      );

      // 3 days × 2 times + 1 day × 1 + 2 days × 1
      expect(slots, hasLength(9));
      expect(slots.first.date, monday);
      expect(slots.first.time, const HourMinute(16, 0));
      // Thursday is covered by no group → no slots that day.
      expect(slots.any((s) => s.date.weekday == DateTime.thursday), isFalse);
    });

    test('overlapping groups merge and dedupe times per day', () {
      final slots = generateSlotsFromGroups(
        startsOn: monday,
        endsOn: monday,
        groups: [
          DayGroup(
              weekdays: {DateTime.monday},
              times: [const HourMinute(17, 0), const HourMinute(16, 0)]),
          DayGroup(
              weekdays: {DateTime.monday},
              times: [const HourMinute(16, 0), const HourMinute(19, 0)]),
        ],
      );

      expect(slots.map((s) => s.time.display()).toList(),
          ['16:00', '17:00', '19:00']);
    });

    test('empty groups produce nothing', () {
      expect(
        generateSlotsFromGroups(
            startsOn: monday, endsOn: sunday, groups: []),
        isEmpty,
      );
    });
  });
}
