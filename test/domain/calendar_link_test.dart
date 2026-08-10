import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';

void main() {
  test('no row means not linked', () {
    expect(CalendarLink.none.status, CalendarLinkStatus.notLinked);
    expect(CalendarLink.none.isLinked, isFalse);
  });

  test('parses a linked row', () {
    final link = CalendarLink.fromJson({
      'user_id': 'u1',
      'status': 'linked',
      'google_email': 'hrac@gmail.com',
      'last_error': null,
      'updated_at': '2026-08-10T07:30:00Z',
    });
    expect(link.status, CalendarLinkStatus.linked);
    expect(link.isLinked, isTrue);
    expect(link.googleEmail, 'hrac@gmail.com');
    expect(link.updatedAt, DateTime.utc(2026, 8, 10, 7, 30));
  });

  test('a broken link keeps the reason for the re-link prompt', () {
    final link = CalendarLink.fromJson({
      'status': 'broken',
      'last_error': 'Google odvolal přístup.',
    });
    expect(link.status, CalendarLinkStatus.broken);
    expect(link.isLinked, isFalse);
    expect(link.lastError, 'Google odvolal přístup.');
  });

  test('reminders parse, and their absence means none', () {
    expect(
      CalendarLink.fromJson({'status': 'linked', 'reminders': '1d2h'}).reminders,
      CalendarReminders.dayAndTwoHours,
    );
    // Rows born before migration 0029 (or an unknown future value) must not
    // break the tile — none is the safe reading.
    expect(CalendarLink.fromJson({'status': 'linked'}).reminders,
        CalendarReminders.none);
    expect(CalendarLink.fromJson({'status': 'linked', 'reminders': 'xyz'})
        .reminders, CalendarReminders.none);
  });

  // The backend may grow states this build has never heard of; anything
  // unknown must read as "not linked" rather than blow up the settings tile.
  test('unknown or missing status falls back to not linked', () {
    expect(CalendarLink.fromJson({'status': 'kdovico'}).status,
        CalendarLinkStatus.notLinked);
    expect(CalendarLink.fromJson(const {}).status,
        CalendarLinkStatus.notLinked);
  });
}
