import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/scrape/gscript.dart';
import 'package:terminator/scrape/scraper.dart';

void main() {
  final body = File('test/fixtures/gscript_callback.txt').readAsStringSync();

  test('parses one term per lane from the schedule grid', () {
    final terms = parseGScriptCallback(body);

    expect(terms, hasLength(120)); // 15 schedule rows × 8 lanes
    expect(terms.where((t) => t.occupied), hasLength(51)); // blank row dropped

    final first = terms.first;
    expect(first.date, Day(2026, 9, 4)); // "pátek 4. 9. 2026"
    expect(first.time, const HourMinute(15, 0)); // "15–17" → start 15:00
    expect(first.occupied, isTrue); // Radim Metelka on lane 1
    expect(first.occupant, contains('TJ Valašské Meziříčí'));
  });

  test('single-digit hour ("9–11") parses as 9:00', () {
    final terms = parseGScriptCallback(body);
    final nine = terms.firstWhere(
        (t) => t.date == Day(2026, 9, 5) && t.time == const HourMinute(9, 0));
    expect(nine, isNotNull);
  });

  test('aggregates per-start occupancy; full and empty starts', () {
    final slots = aggregateTerms(parseGScriptCallback(body));

    expect(slots, hasLength(15));

    final friday15 = slots[0];
    expect(friday15.date, Day(2026, 9, 4));
    expect(friday15.time, const HourMinute(15, 0));
    expect(friday15.capacity, 8);
    expect(friday15.occupied, 4);
    expect(friday15.free, 4);

    final friday17 = slots[1];
    expect(friday17.time, const HourMinute(17, 0));
    expect(friday17.occupied, 8);
    expect(friday17.free, 0);
  });

  test('ourNeedle matches occupant club text', () {
    // Friday 17–19 is fully booked by "Tereza Nová / KK MS Brno".
    final slots =
        aggregateTerms(parseGScriptCallback(body), ourNeedle: 'kk ms brno');
    final friday17 = slots[1];
    expect(friday17.occupiedOurs, 8);
    expect(slots[0].occupiedOurs, 0); // Friday 15–17: other clubs
  });

  test('reads the tournament name from settings', () {
    expect(parseGScriptName(body), 'Hanácká 240');
  });

  test('registry recognizes script.google.com /macros/ URLs', () {
    final scraper = ScraperRegistry.forUrl(
      'https://script.google.com/macros/s/AKfycbwc4rRDR4k_XvGCabrdAtF3'
      'WIdTzCU9WSFClPnnsoI6C8mbAYUMwmwWTBNoUjZFigWOFA/exec?fbclid=IwXYZ',
    );
    expect(scraper, isA<GScriptScraper>());
    // Other hosts stay with their scrapers / null.
    expect(ScraperRegistry.forUrl('https://example.com/x'), isNull);
  });

  test('callback URL is derived from the pasted /exec URL', () {
    final url = gscriptCallbackUrl(Uri.parse(
      'https://script.google.com/macros/s/DEPLOY_ID_123/exec?fbclid=IwXYZ',
    ));
    expect(url.host, 'script.google.com');
    expect(url.path, '/macros/s/DEPLOY_ID_123/callback');
  });
}
