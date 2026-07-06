import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/domain/slot_generator.dart';

void main() {
  // 2026-04-20 is a Monday, 2026-04-26 the following Sunday.
  final monday = Day(2026, 4, 20);
  final sunday = Day(2026, 4, 26);
  final weekday = [const HourMinute(16, 0), const HourMinute(17, 30)];
  final weekend = [const HourMinute(10, 0)];

  test('generates weekday times Mon-Fri and weekend times Sat-Sun', () {
    final slots = generateSlots(
      startsOn: monday,
      endsOn: sunday,
      weekdayTimes: weekday,
      weekendTimes: weekend,
    );

    // 5 weekdays × 2 times + 2 weekend days × 1 time
    expect(slots, hasLength(12));
    expect(slots.first, SlotSpec(monday, const HourMinute(16, 0)));
    expect(slots.last, SlotSpec(sunday, const HourMinute(10, 0)));
    expect(
      slots.where((s) => s.date.isWeekend).length,
      2,
    );
  });

  test('sorts by date then time even when patterns are unsorted', () {
    final slots = generateSlots(
      startsOn: monday,
      endsOn: monday,
      weekdayTimes: [const HourMinute(18, 0), const HourMinute(16, 30)],
      weekendTimes: const [],
    );

    expect(slots.map((s) => s.time.display()).toList(), ['16:30', '18:00']);
  });

  test('empty pattern produces no slots for those days', () {
    final slots = generateSlots(
      startsOn: monday,
      endsOn: sunday,
      weekdayTimes: const [],
      weekendTimes: weekend,
    );

    expect(slots, hasLength(2));
    expect(slots.every((s) => s.date.isWeekend), isTrue);
  });

  test('range ending before start produces nothing', () {
    final slots = generateSlots(
      startsOn: sunday,
      endsOn: monday,
      weekdayTimes: weekday,
      weekendTimes: weekend,
    );

    expect(slots, isEmpty);
  });

  test('single-day tournament works', () {
    final slots = generateSlots(
      startsOn: sunday,
      endsOn: sunday,
      weekdayTimes: weekday,
      weekendTimes: weekend,
    );

    expect(slots, hasLength(1));
    expect(slots.single.date, sunday);
  });
}
