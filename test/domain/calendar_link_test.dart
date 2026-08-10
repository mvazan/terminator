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

  test('reminder minutes parse sorted farthest-first; absence means none', () {
    expect(
      CalendarLink.fromJson({
        'status': 'linked',
        'reminder_minutes': [120, 1440],
      }).reminderMinutes,
      [1440, 120],
    );
    // Rows born before migration 0030 must not break the tile.
    expect(CalendarLink.fromJson({'status': 'linked'}).reminderMinutes,
        isEmpty);
  });

  test('offsets read as humans say them', () {
    expect(reminderOffsetLabel(0), 'V čase startu');
    expect(reminderOffsetLabel(45), '45 min předem');
    expect(reminderOffsetLabel(120), '2 h předem');
    expect(reminderOffsetLabel(1440), '1 den předem');
    expect(reminderOffsetLabel(2880), '2 dny předem');
    expect(reminderOffsetLabel(7 * 1440), '7 dní předem');
    expect(reminderOffsetLabel(90), '90 min předem'); // no clean hour
  });

  test('summary joins from the farthest, empty reads as none', () {
    expect(remindersSummary(const []), 'Žádné');
    expect(remindersSummary(const [120, 2880]),
        '2 dny předem · 2 h předem');
  });

  // A cleanly disconnected row stays behind as 'unlinked' (it keeps the
  // reminder preference); the tile must read that as "offer Propojit".
  test('unlinked reads as not linked', () {
    final link = CalendarLink.fromJson({
      'status': 'unlinked',
      'reminder_minutes': [1440],
    });
    expect(link.status, CalendarLinkStatus.notLinked);
    expect(link.isLinked, isFalse);
    // The preference survives for the next link.
    expect(link.reminderMinutes, [1440]);
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
