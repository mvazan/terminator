/// Scraper for tournament reservation web-apps built on Google Apps Script
/// (script.google.com/macros/s/&lt;deployment&gt;/exec), as used by HKK Olomouc
/// for "Hanácká 240".
///
/// Unlike the other scrapers there is no HTML to parse: the /exec page is an
/// empty shell that loads its data over Apps Script's RPC channel. The same
/// channel is called directly — POST to the deployment's `/callback` endpoint
/// with the `X-Same-Domain: 1` header (Google's CSRF check; the XSRF token is
/// empty for anonymous web-apps) and a form body naming the server function:
///
///     request=["getPublicData","[]",null,[0],null,null,true,0]
///
/// The response is a `)]}'` guard line plus `[["op.exec",[0,"<json>"]]]`
/// where &lt;json&gt; is `{settings, schedule, reservations}`
/// (see test/fixtures/gscript_callback.txt):
///   - schedule:     {day: "pátek 4. 9. 2026", time: "15–17", lanes: 8}
///   - reservations: {day, time, lane, name, club} — one per booked lane
/// A lane-start is free when no reservation matches its (day, time, lane).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'scraper.dart';

class GScriptScraper implements TournamentScraper {
  GScriptScraper({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  String get name => 'script.google.com (rezervace)';

  @override
  Future<ScrapeResult> fetch(Uri url, {String ourTeam = ''}) async {
    final callback = gscriptCallbackUrl(url).replace(queryParameters: {
      'nocache_id': DateTime.now().microsecondsSinceEpoch.toString(),
    });
    final response = await _client.post(
      callback,
      headers: {'X-Same-Domain': '1'},
      body: {'request': '["getPublicData","[]",null,[0],null,null,true,0]'},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Stránka vrátila ${response.statusCode}');
    }
    final body = utf8.decode(response.bodyBytes);
    return ScrapeResult(
      slots: aggregateTerms(parseGScriptCallback(body), ourNeedle: ourTeam),
      name: parseGScriptName(body),
    );
  }
}

final _deploymentPattern = RegExp(r'/macros/s/([A-Za-z0-9_-]+)');

/// The RPC endpoint for the deployment in a pasted …/exec URL.
Uri gscriptCallbackUrl(Uri url) {
  final m = _deploymentPattern.firstMatch(url.path);
  if (m == null) {
    throw Exception('V adrese chybí /macros/s/<id>');
  }
  return Uri.https('script.google.com', '/macros/s/${m.group(1)}/callback');
}

/// The `{settings, schedule, reservations}` object out of the RPC envelope;
/// null when the response has some other shape.
Map<String, dynamic>? _decodePayload(String body) {
  final json = body.replaceFirst(RegExp(r"^\)\]\}'"), '').trim();
  final dynamic outer;
  try {
    outer = jsonDecode(json);
  } on FormatException {
    return null;
  }
  if (outer is! List) return null;
  for (final entry in outer) {
    if (entry is List &&
        entry.length >= 2 &&
        entry[0] == 'op.exec' &&
        entry[1] is List &&
        (entry[1] as List).length >= 2 &&
        (entry[1] as List)[1] is String) {
      final decoded = jsonDecode((entry[1] as List)[1] as String);
      return decoded is Map<String, dynamic> ? decoded : null;
    }
  }
  return null;
}

// The page matches schedule cells to reservations on raw day/time strings;
// mirror its normalization (trim, lowercase, collapse spaces, dashes → "-").
String _norm(Object? v) => (v ?? '')
    .toString()
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'[–—]'), '-');

final _dayPattern = RegExp(r'(\d{1,2})\.\s*(\d{1,2})\.\s*(\d{4})');
final _startTimePattern = RegExp(r'^(\d{1,2})(?::(\d{2}))?');

/// "pátek 4. 9. 2026" → Day; null when no date is present.
Day? _parseDay(Object? raw) {
  final m = _dayPattern.firstMatch(raw?.toString() ?? '');
  if (m == null) return null;
  return Day(
    int.parse(m.group(3)!),
    int.parse(m.group(2)!),
    int.parse(m.group(1)!),
  );
}

/// "15–17" / "9:30–11" → start time; null when none.
HourMinute? _parseStartTime(Object? raw) {
  final m = _startTimePattern.firstMatch(_norm(raw));
  if (m == null) return null;
  return HourMinute(int.parse(m.group(1)!), int.parse(m.group(2) ?? '0'));
}

/// Tournament name from settings; null when the payload doesn't carry one.
String? parseGScriptName(String body) {
  final settings = _decodePayload(body)?['settings'];
  if (settings is! Map) return null;
  final name = settings['tournamentName']?.toString().trim() ?? '';
  return name.isEmpty ? null : name;
}

/// Pure parser — one term per lane of every schedule row, occupied when a
/// reservation matches its (day, time, lane). Unit-tested against a fixture
/// of a real /callback response.
List<VenueTerm> parseGScriptCallback(String body) {
  final data = _decodePayload(body);
  if (data == null) return [];
  final schedule = data['schedule'];
  final reservations = data['reservations'];

  // (day|time|lane) → occupant "name club".
  final occupants = <String, String>{};
  if (reservations is List) {
    for (final r in reservations) {
      if (r is! Map) continue;
      final key =
          '${_norm(r['day'])}|${_norm(r['time'])}|${_norm(r['lane'])}';
      if (key == '||') continue; // blank sheet rows
      occupants[key] =
          '${r['name'] ?? ''} ${r['club'] ?? ''}'.trim();
    }
  }

  final terms = <VenueTerm>[];
  if (schedule is! List) return terms;
  for (final row in schedule) {
    if (row is! Map) continue;
    final date = _parseDay(row['day']);
    final time = _parseStartTime(row['time']);
    final lanes = int.tryParse(row['lanes']?.toString() ?? '') ?? 0;
    if (date == null || time == null) continue;
    for (var lane = 1; lane <= lanes; lane++) {
      final occupant =
          occupants['${_norm(row['day'])}|${_norm(row['time'])}|$lane'];
      terms.add(VenueTerm(
        date: date,
        time: time,
        occupied: occupant != null,
        occupant: occupant ?? '',
      ));
    }
  }
  return terms;
}
