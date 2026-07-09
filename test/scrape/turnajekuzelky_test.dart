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

  test('221: pairs (2x120HS) — kind is dvojice, lane occupancy read per lane',
      () {
    final r = parseTurnajeKuzelkyHtml(fixture('221'));

    expect(r.name, '17. ročník Memoriálu Stanislava Zálešáka');
    // The 2 in "2x120HS" means dvojice — two players share one ordered lane,
    // which the app's TournamentKind handles; the scraper still counts lanes.
    expect(r.kind, TournamentKind.dvojice);
    expect(r.discipline, Discipline.hs120);

    final byTime = {for (final s in r.slots) '${s.date} ${s.time}': s};
    // 20.7. 17:00 — two lanes, both taken.
    final full = byTime['2026-07-20 17:00'];
    expect(full, isNotNull);
    expect(full!.capacity, 2);
    expect(full.occupied, 2);
    expect(full.free, 0);
    // 20.7. 20:00 — two lanes, both free.
    final open = byTime['2026-07-20 20:00'];
    expect(open!.capacity, 2);
    expect(open.free, 2);
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
