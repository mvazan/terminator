import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/scrape/galanta.dart';
import 'package:terminator/scrape/scraper.dart';

void main() {
  final html = File('test/fixtures/galanta_sample.html').readAsStringSync();

  test('parses lane-starts with date (DD.MM.YYYY), time and occupancy', () {
    final terms = parseGalantaHtml(html);

    expect(terms, hasLength(8)); // 4 lanes × 2 starts
    expect(terms.where((t) => t.occupied), hasLength(3)); // 2 + 1 booked

    final first = terms.first;
    expect(first.date, Day(2026, 7, 11));
    expect(first.time, const HourMinute(10, 0));
    expect(first.occupied, isTrue); // Milan Kováč booked

    // A free lane (booking form) is not occupied.
    final free = terms.firstWhere((t) => !t.occupied);
    expect(free.occupied, isFalse);
  });

  test('aggregates into per-start occupancy (one lane per row)', () {
    final slots = aggregateTerms(parseGalantaHtml(html));

    expect(slots, hasLength(2));

    final ten = slots[0];
    expect(ten.date, Day(2026, 7, 11));
    expect(ten.time, const HourMinute(10, 0));
    expect(ten.capacity, 4);
    expect(ten.occupied, 2);
    expect(ten.free, 2);

    final eleven = slots[1];
    expect(eleven.time, const HourMinute(11, 0));
    expect(eleven.capacity, 4);
    expect(eleven.occupied, 1);
    expect(eleven.free, 3);
  });

  test('occupant text includes the klub cell; ourNeedle counts our lanes', () {
    final terms = parseGalantaHtml(html);
    final booked = terms.where((t) => t.occupied).toList();
    expect(booked.first.occupant, contains('Sučany')); // Milan Kováč's klub

    // Case-insensitive contains on the whole row text (name + klub).
    final slots = aggregateTerms(terms, ourNeedle: 'sučany');
    final ten = slots[0];
    expect(ten.occupiedOurs, 1); // only Kováč's lane, not Janík's
    expect(ten.occupied, 2);
  });

  test('reads the tournament name from the "- prihláška" heading', () {
    expect(parseGalantaName(html), 'Memoriál ZOLIHO MADARÁSA 2026');
  });

  test('page without a reservation grid parses to empty', () {
    expect(parseGalantaHtml('<html><body>Nic tu není</body></html>'), isEmpty);
  });

  test('ScraperRegistry recognizes kolky-galanta.sk', () {
    expect(
      ScraperRegistry.forUrl(
          'https://www.kolky-galanta.sk/ga24/turnaj_prihlaska.php?id_turnaj=56'),
      isA<GalantaScraper>(),
    );
  });

  test('ScraperRegistry still recognizes the others and rejects junk', () {
    expect(ScraperRegistry.forUrl('https://www.turnajekuzelky.cz/x'),
        isNotNull);
    expect(ScraperRegistry.forUrl('https://kkmoravskaslavia.cz/x'), isNotNull);
    expect(ScraperRegistry.forUrl('https://example.com/x'), isNull);
  });
}
