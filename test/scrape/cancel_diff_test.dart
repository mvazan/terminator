import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/scrape/scraper.dart';

Slot _slot(
  String id,
  Day date,
  HourMinute time, {
  int? venueCapacity = 8,
  DateTime? cancelledAt,
}) =>
    Slot(
      id: id,
      tournamentId: 't1',
      date: date,
      time: time,
      venueCapacity: venueCapacity,
      cancelledAt: cancelledAt,
    );

VenueSlot _fresh(Day date, HourMinute time) =>
    VenueSlot(date: date, time: time, capacity: 8, occupied: 0);

void main() {
  final d = Day(2026, 9, 5);
  final now = Day(2026, 9, 1);

  test('scraped slot missing from the fresh page gets cancelled', () {
    final diff = diffCancelledSlots(
      existing: [
        _slot('a', d, const HourMinute(10, 0)),
        _slot('b', d, const HourMinute(12, 0)),
      ],
      fresh: [_fresh(d, const HourMinute(10, 0))],
      today: now,
    );
    expect(diff.cancel, ['b']);
    expect(diff.revive, isEmpty);
  });

  test('already-played day missing from the page is left alone', () {
    // Some sources hide days that were already played; the app hides them
    // too, so their disappearance is routine — not a venue cancellation.
    final diff = diffCancelledSlots(
      existing: [
        _slot('a', d, const HourMinute(16, 0)),
        _slot('b', d, const HourMinute(17, 0)),
      ],
      fresh: const [],
      today: d.addDays(2),
    );
    expect(diff.cancel, isEmpty);
    expect(diff.revive, isEmpty);
  });

  test("today's missing slot still counts as cancelled", () {
    // Today is not "played" yet — the app still shows it, so a vanished
    // start today must cancel (and notify) as before.
    final diff = diffCancelledSlots(
      existing: [_slot('a', d, const HourMinute(16, 0))],
      fresh: const [],
      today: d,
    );
    expect(diff.cancel, ['a']);
    expect(diff.revive, isEmpty);
  });

  test('manual slot (no venue info) is never auto-cancelled', () {
    final diff = diffCancelledSlots(
      existing: [_slot('m', d, const HourMinute(14, 0), venueCapacity: null)],
      fresh: [_fresh(d, const HourMinute(10, 0))],
      today: now,
    );
    expect(diff.cancel, isEmpty);
    expect(diff.revive, isEmpty);
  });

  test('cancelled slot that reappears on the page is revived', () {
    final diff = diffCancelledSlots(
      existing: [
        _slot('a', d, const HourMinute(10, 0),
            cancelledAt: DateTime.utc(2026, 8, 1)),
      ],
      fresh: [_fresh(d, const HourMinute(10, 0))],
      today: now,
    );
    expect(diff.cancel, isEmpty);
    expect(diff.revive, ['a']);
  });

  test('already-cancelled slot still missing is left alone (no re-trigger)',
      () {
    final diff = diffCancelledSlots(
      existing: [
        _slot('a', d, const HourMinute(10, 0),
            cancelledAt: DateTime.utc(2026, 8, 1)),
      ],
      fresh: [_fresh(d, const HourMinute(12, 0))],
      today: now,
    );
    expect(diff.cancel, isEmpty);
    expect(diff.revive, isEmpty);
  });

  test('Slot.fromJson reads cancelled_at; cancelled getter follows it', () {
    final slot = Slot.fromJson({
      'id': 's1',
      'tournament_id': 't1',
      'date': '2026-09-05',
      'time': '10:00',
      'venue_capacity': 8,
      'venue_occupied': 2,
      'venue_occupied_ours': 0,
      'cancelled_at': '2026-08-12T10:00:00Z',
    });
    expect(slot.cancelled, isTrue);
    expect(Slot.fromJson({
      'id': 's2',
      'tournament_id': 't1',
      'date': '2026-09-05',
      'time': '10:00',
    }).cancelled, isFalse);
  });
}
