/// Scraper for reservation pages of the mkware.eu system, as used by
/// kkmoravskaslavia.cz (and other kuželky clubs running the same software).
///
/// Page anatomy (see test/fixtures/mkware_sample.html): one `<tr>` per
/// bookable lane-start with `id="YYYY-MM-DD-<lane>"`, a time cell
/// "16:00 - 16:49", and —
/// when the lane-start is still free — an empty booking form containing
/// `placeholder="Name"`. A row without that form is booked.
library;

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'scraper.dart';

class MkwareScraper implements TournamentScraper {
  MkwareScraper({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  String get name => 'mkware (kkmoravskaslavia.cz)';

  @override
  Future<List<VenueSlot>> fetch(Uri url) async {
    final response = await _client.get(url).timeout(
          const Duration(seconds: 20),
        );
    if (response.statusCode != 200) {
      throw Exception('Stránka vrátila ${response.statusCode}');
    }
    return aggregateTerms(parseMkwareHtml(response.body));
  }
}

final _rowPattern = RegExp(
  r'<tr id="(\d{4}-\d{2}-\d{2})-\d+">(.*?)</tr>',
  dotAll: true,
);
final _timePattern = RegExp(r'(\d{1,2}:\d{2})\s*-');

/// Pure parser — unit-tested against a fixture of the real page.
List<VenueTerm> parseMkwareHtml(String html) {
  final terms = <VenueTerm>[];
  for (final row in _rowPattern.allMatches(html)) {
    final body = row.group(2)!;
    final timeMatch = _timePattern.firstMatch(body);
    if (timeMatch == null) continue;
    terms.add(VenueTerm(
      date: Day.parse(row.group(1)!),
      time: HourMinute.parse(timeMatch.group(1)!),
      // A free lane-start renders an empty booking form; a booked one
      // renders the reservation as plain text without the form.
      occupied: !body.contains('placeholder="Name"'),
    ));
  }
  return terms;
}
