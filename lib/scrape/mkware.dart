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
  Future<ScrapeResult> fetch(Uri url) async {
    final response = await _client.get(url).timeout(
          const Duration(seconds: 20),
        );
    if (response.statusCode != 200) {
      throw Exception('Stránka vrátila ${response.statusCode}');
    }
    final html = response.body;
    return ScrapeResult(
      slots: aggregateTerms(parseMkwareHtml(html)),
      name: parseMkwareName(html),
      kind: parseMkwareKind(html),
      discipline: parseMkwareDiscipline(html),
    );
  }
}

final _rowPattern = RegExp(
  r'<tr id="(\d{4}-\d{2}-\d{2})-\d+">(.*?)</tr>',
  dotAll: true,
);
final _timePattern = RegExp(r'(\d{1,2}:\d{2})\s*-');

// The page names the tournament in an <h2> and describes the format in free
// text, e.g. "… turnaj dvojic na 100 HS dle pravidel ČKA."
final _h2Pattern = RegExp(r'<h2[^>]*>(.*?)</h2>', dotAll: true);
final _formatPattern = RegExp(
  r'turnaj\s+(jednotlivc\w*|dvojic\w*|čtveřic\w*|tandem\w*)\s+na\s+(\d+)\s*HS',
  caseSensitive: false,
);

/// Tournament name from the page's <h2>, tags stripped.
String? parseMkwareName(String html) {
  final m = _h2Pattern.firstMatch(html);
  if (m == null) return null;
  final name = m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
  return name.isEmpty ? null : name;
}

/// Kind from the "turnaj X na …" description.
TournamentKind? parseMkwareKind(String html) {
  final m = _formatPattern.firstMatch(html);
  if (m == null) return null;
  final word = m.group(1)!.toLowerCase();
  if (word.startsWith('jednotlivc')) return TournamentKind.jednotlivci;
  if (word.startsWith('dvojic')) return TournamentKind.dvojice;
  if (word.startsWith('čtveřic')) return TournamentKind.ctverice;
  if (word.startsWith('tandem')) return TournamentKind.tandem;
  return null;
}

/// Discipline from the "… na N HS" description.
Discipline? parseMkwareDiscipline(String html) {
  final m = _formatPattern.firstMatch(html);
  if (m == null) return null;
  return Discipline.tryParse('${m.group(2)}HS');
}

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
