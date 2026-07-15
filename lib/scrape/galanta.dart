/// Scraper for the online sign-up pages of kolky-galanta.sk (MKK Slovan
/// Galanta's `turnaj_prihlaska.php`). Same shape as mkware: one table row per
/// bookable lane-start.
///
/// Page anatomy (see test/fixtures/galanta_sample.html): each lane-start is a
/// `<tr>` whose first cell reads "sobota <br> 11.07.2026 10:00" (weekday,
/// DD.MM.YYYY date, HH:MM time). A still-free lane renders a booking form
/// (`<input name=jmeno>`); a booked one shows the player's name as plain text.
/// The tournament name sits in a bold `NAME - prihláška` heading; the page
/// carries no kind/discipline, so those are left for the user.
library;

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'scraper.dart';

class GalantaScraper implements TournamentScraper {
  GalantaScraper({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  String get name => 'kolky-galanta.sk';

  @override
  Future<ScrapeResult> fetch(Uri url) async {
    final response = await _client.get(url).timeout(
          const Duration(seconds: 20),
        );
    if (response.statusCode != 200) {
      throw Exception('Stránka vrátila ${response.statusCode}');
    }
    final html = response.body;
    return ScrapeResult(
      slots: aggregateTerms(parseGalantaHtml(html)),
      name: parseGalantaName(html),
    );
  }
}

final _rowPattern = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true);
final _dateTimePattern =
    RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{4})\s+(\d{1,2}):(\d{2})');
// The tournament name is the bold "NAME - prihláška" heading. [^<] keeps the
// match inside that single <b>'s text so it can't run back to an earlier bold
// element (e.g. the "[ Hlavné menu … ]" bar).
final _namePattern = RegExp(
  r'<b>\s*([^<]*?)\s*-\s*prihláška',
  caseSensitive: false,
);

/// Tournament name from the "… - prihláška" heading.
String? parseGalantaName(String html) {
  final m = _namePattern.firstMatch(html);
  if (m == null) return null;
  final name = m.group(1)!.trim();
  return name.isEmpty ? null : name;
}

/// Pure parser — unit-tested against a fixture of the real page. One term per
/// lane-start row (each row is one lane, so the aggregate capacity is the lane
/// count for that start).
List<VenueTerm> parseGalantaHtml(String html) {
  final terms = <VenueTerm>[];
  for (final row in _rowPattern.allMatches(html)) {
    final body = row.group(1)!;
    final dt = _dateTimePattern.firstMatch(body);
    if (dt == null) continue; // header/decoration rows have no date+time
    terms.add(VenueTerm(
      date: Day(
        int.parse(dt.group(3)!),
        int.parse(dt.group(2)!),
        int.parse(dt.group(1)!),
      ),
      time: HourMinute(int.parse(dt.group(4)!), int.parse(dt.group(5)!)),
      // A free lane renders a booking form (<input name=jmeno>); a booked one
      // shows the player's name as plain text.
      occupied: !body.contains('name=jmeno'),
    ));
  }
  return terms;
}
