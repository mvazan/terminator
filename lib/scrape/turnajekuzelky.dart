/// Scraper for turnajekuzelky.cz tournament pages.
///
/// Page anatomy (see test/fixtures/turnajekuzelky_*.html):
///   - the format badge  `<i class="fas fa-gamepad …"></i> 2x120HS`
///     — the leading digit is players-per-start (1 → jednotlivci, 2 → dvojice,
///       4 → čtveřice); the `…HS` part is the discipline.
///   - `<title>Název – Termíny | Turnaje kuželky</title>` — tournament name.
///   - one day block per `<div class="date-header"> … 20. 07. 2026 …`.
///   - inside it, one bookable lane-start per
///     `<div class="slot-row slot-taken|slot-free"><div class="slot-time">HH:MM`.
///     A free start says "Volný termín"; a taken one lists the player name(s).
///
/// Occupancy is per lane — the same model as mkware. How many *players* sit on
/// a lane (2 for dvojice, etc.) is the tournament's kind, applied by the app,
/// not the scraper: the scraper only reports lanes free/taken.
library;

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'scraper.dart';

class TurnajeKuzelkyScraper implements TournamentScraper {
  TurnajeKuzelkyScraper({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  String get name => 'turnajekuzelky.cz';

  @override
  Future<ScrapeResult> fetch(Uri url) async {
    final response = await _client.get(url).timeout(
          const Duration(seconds: 20),
        );
    if (response.statusCode != 200) {
      throw Exception('Stránka vrátila ${response.statusCode}');
    }
    return parseTurnajeKuzelkyHtml(response.body);
  }
}

final _dayHeaderPattern =
    RegExp(r'date-header.*?(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})', dotAll: true);
final _slotRowPattern = RegExp(
  r'slot-row\s+(slot-taken|slot-free)"[^>]*>\s*'
  r'<div class="slot-time">\s*(\d{1,2}:\d{2})',
  dotAll: true,
);
final _gamepadPattern =
    RegExp(r'fa-gamepad[^>]*></i>\s*(\d+)x(\d+HS)');
final _titlePattern = RegExp(r'<title>\s*(.*?)\s*</title>', dotAll: true);

/// Pure parser — unit-tested against fixtures of the real pages.
ScrapeResult parseTurnajeKuzelkyHtml(String html) {
  // Split into day blocks so each slot-row is attributed to its date-header.
  final headers = _dayHeaderPattern.allMatches(html).toList();
  final terms = <VenueTerm>[];
  for (var i = 0; i < headers.length; i++) {
    final h = headers[i];
    final blockEnd = i + 1 < headers.length ? headers[i + 1].start : html.length;
    final block = html.substring(h.end, blockEnd);
    final date = Day(
      int.parse(h.group(3)!),
      int.parse(h.group(2)!),
      int.parse(h.group(1)!),
    );
    for (final row in _slotRowPattern.allMatches(block)) {
      terms.add(VenueTerm(
        date: date,
        time: HourMinute.parse(row.group(2)!),
        occupied: row.group(1) == 'slot-taken',
      ));
    }
  }

  return ScrapeResult(
    // The "N×" in the format is how many players share one start (dvojice → 2),
    // so a start's places = starts × N. Two free 2× starts at 16:00 → 0/4.
    slots: aggregateTerms(terms, playersPerTerm: _parsePlayersPerStart(html)),
    name: _parseName(html),
    kind: _parseKind(html),
    discipline: _parseDiscipline(html),
  );
}

/// The leading "N" of "2x120HS" — players per start. Defaults to 1 if unknown.
int _parsePlayersPerStart(String html) {
  final m = _gamepadPattern.firstMatch(html);
  return m == null ? 1 : (int.tryParse(m.group(1)!) ?? 1);
}

/// "Memoriál Pavla Mila – Termíny | Turnaje kuželky" → "Memoriál Pavla Mila".
String? _parseName(String html) {
  final m = _titlePattern.firstMatch(html);
  if (m == null) return null;
  var title = m.group(1)!;
  for (final sep in [' – Termíny', ' - Termíny', ' | Turnaje']) {
    final i = title.indexOf(sep);
    if (i >= 0) title = title.substring(0, i);
  }
  title = title.trim();
  return title.isEmpty ? null : title;
}

/// Leading digit of "2x120HS" → players per start → kind.
TournamentKind? _parseKind(String html) {
  final m = _gamepadPattern.firstMatch(html);
  if (m == null) return null;
  switch (m.group(1)) {
    case '1':
      return TournamentKind.jednotlivci;
    case '2':
      return TournamentKind.dvojice;
    case '3':
      return TournamentKind.trojice;
    case '4':
      return TournamentKind.ctverice;
    default:
      return null;
  }
}

/// "120HS" part of "2x120HS", mapped to a Discipline if we know it.
Discipline? _parseDiscipline(String html) {
  final m = _gamepadPattern.firstMatch(html);
  if (m == null) return null;
  return Discipline.tryParse(m.group(2)!);
}
