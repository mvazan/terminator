import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/scrape/scraper.dart';
import 'package:terminator/scrape/turnajekuzelky.dart';

void main() {
  String fixture(String id) =>
      File('test/fixtures/turnajekuzelky_$id.html').readAsStringSync();

  test('219: singles (1x120HS) — name, kind, discipline, occupancy', () {
    final r = parseTurnajeKuzelkyHtml(fixture('219'));

    expect(r.name, 'Memoriál Pavla Mila');
    expect(r.kind, TournamentKind.jednotlivci);
    expect(r.discipline, Discipline.hs120);

    // First day, 10:00 — four lanes, all free.
    final first = r.slots.first;
    expect(first.date, Day(2026, 8, 15));
    expect(first.time, const HourMinute(10, 0));
    expect(first.capacity, 4);
    expect(first.occupied, 0);
    expect(first.free, 4);
  });

  test('221: pairs (2x120HS) — capacity counts player places, not starts', () {
    final r = parseTurnajeKuzelkyHtml(fixture('221'));

    expect(r.name, '17. ročník Memoriálu Stanislava Zálešáka');
    expect(r.kind, TournamentKind.dvojice);
    expect(r.discipline, Discipline.hs120);

    final byTime = {for (final s in r.slots) '${s.date} ${s.time}': s};
    // "2x" means two players per start, so each start row is 2 places. 20.7.
    // 17:00 has two taken starts → 4 places, all taken.
    final full = byTime['2026-07-20 17:00'];
    expect(full, isNotNull);
    expect(full!.capacity, 4);
    expect(full.occupied, 4);
    expect(full.free, 0);
    // 20.7. 20:00 — two free starts → 4 places free (shown as 0/4).
    final open = byTime['2026-07-20 20:00'];
    expect(open!.capacity, 4);
    expect(open.occupied, 0);
    expect(open.free, 4);
  });

  test('page without a reservation grid parses to empty slots', () {
    final r = parseTurnajeKuzelkyHtml('<html><body>zavřeno</body></html>');
    expect(r.slots, isEmpty);
    expect(r.name, isNull);
    expect(r.kind, isNull);
  });

  group('ScraperRegistry', () {
    test('recognizes turnajekuzelky.cz', () {
      expect(
        ScraperRegistry.forUrl('https://turnajekuzelky.cz/turnaj/221'),
        isA<TurnajeKuzelkyScraper>(),
      );
    });

    test('still recognizes mkware and rejects the rest', () {
      expect(
        ScraperRegistry.forUrl(
            'https://kkmoravskaslavia.cz/mkware/turnaj.php?idt=513'),
        isNotNull,
      );
      expect(ScraperRegistry.forUrl('https://example.com/turnaj'), isNull);
    });
  });
}
