import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/scrape/mkware.dart';
import 'package:terminator/scrape/scraper.dart';

void main() {
  final html =
      File('test/fixtures/mkware_sample.html').readAsStringSync();

  test('parses lane-starts with date, time and occupancy', () {
    final terms = parseMkwareHtml(html);

    expect(terms, hasLength(8));
    expect(terms.where((t) => t.occupied), hasLength(2));

    final first = terms.first;
    expect(first.date, Day(2026, 7, 31));
    expect(first.time, const HourMinute(16, 0));
    expect(first.occupied, isFalse);
  });

  test('captures the occupant text and counts our bookings', () {
    final terms = parseMkwareHtml(html);
    final booked = terms.where((t) => t.occupied).toList();
    expect(booked.first.occupant, contains('KK Veverky'));
    expect(terms.where((t) => !t.occupied).every((t) => t.occupant.isEmpty),
        isTrue);

    final slots = aggregateTerms(terms, ourNeedle: 'veverky');
    final sixteen = slots[0]; // 31.07 16:00 — booked by KK Veverky
    expect(sixteen.occupiedOurs, 1);
    // The other booked start (Sokol) isn't ours.
    expect(slots.fold(0, (n, s) => n + s.occupiedOurs), 1);
  });

  test('aggregates into per-start occupancy', () {
    final slots = aggregateTerms(parseMkwareHtml(html));

    expect(slots, hasLength(3));

    final sixteen = slots[0];
    expect(sixteen.date, Day(2026, 7, 31));
    expect(sixteen.time, const HourMinute(16, 0));
    expect(sixteen.capacity, 5);
    expect(sixteen.occupied, 1);
    expect(sixteen.free, 4);

    final halfPastSixteen = slots[1];
    expect(halfPastSixteen.time, const HourMinute(16, 50));
    expect(halfPastSixteen.capacity, 2);
    expect(halfPastSixteen.occupied, 0);

    final fullyBooked = slots[2];
    expect(fullyBooked.date, Day(2026, 8, 1));
    expect(fullyBooked.capacity, 1);
    expect(fullyBooked.free, 0);
  });

  test('page without a reservation grid parses to empty', () {
    expect(parseMkwareHtml('<html><body>closed</body></html>'), isEmpty);
  });

  test('detects name, kind and discipline from the page header/description',
      () {
    expect(parseMkwareName(html), 'Memoriál Josefa Vinklara 2026 - TJ Sokol '
        'Mistřín');
    expect(parseMkwareKind(html), TournamentKind.dvojice); // "turnaj dvojic"
    expect(parseMkwareDiscipline(html), Discipline.hs100); // "na 100 HS"
  });

  test('metadata parsers return null when the page lacks them', () {
    const bare = '<html><body>closed</body></html>';
    expect(parseMkwareName(bare), isNull);
    expect(parseMkwareKind(bare), isNull);
    expect(parseMkwareDiscipline(bare), isNull);
  });

  group('ScraperRegistry', () {
    test('recognizes kkmoravskaslavia and mkware paths', () {
      expect(
        ScraperRegistry.forUrl(
            'https://kkmoravskaslavia.cz/mkware/turnaj-tjsokolmistrin.php?idt=513'),
        isNotNull,
      );
      expect(
        ScraperRegistry.forUrl('https://jinyklub.cz/mkware/turnaj.php?idt=1'),
        isNotNull,
      );
    });

    test('rejects unknown urls and garbage', () {
      expect(ScraperRegistry.forUrl('https://example.com/turnaj'), isNull);
      expect(ScraperRegistry.forUrl('not a url'), isNull);
      expect(ScraperRegistry.forUrl(''), isNull);
    });
  });
}
