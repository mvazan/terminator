/// Tournament-page scraping: import the start grid and live occupancy from
/// the organizer's reservation page instead of typing slots by hand.
///
/// A scraper is chosen by URL. Unrecognized URLs get no scraper — the UI then
/// only offers manual slot entry.
library;

import '../domain/models.dart';
import 'mkware.dart';
import 'turnajekuzelky.dart';

/// One bookable lane-start scraped from the page.
class VenueTerm {
  const VenueTerm({
    required this.date,
    required this.time,
    required this.occupied,
  });

  final Day date;
  final HourMinute time;
  final bool occupied;
}

/// Occupancy of one start time: how many lanes exist / are already booked.
class VenueSlot {
  const VenueSlot({
    required this.date,
    required this.time,
    required this.capacity,
    required this.occupied,
  });

  final Day date;
  final HourMinute time;
  final int capacity;
  final int occupied;

  int get free => capacity - occupied;
}

/// Groups raw lane-starts into per-(date, time) occupancy.
List<VenueSlot> aggregateTerms(List<VenueTerm> terms) {
  final byKey = <String, List<VenueTerm>>{};
  for (final term in terms) {
    byKey.putIfAbsent('${term.date}|${term.time}', () => []).add(term);
  }
  final slots = [
    for (final group in byKey.values)
      VenueSlot(
        date: group.first.date,
        time: group.first.time,
        capacity: group.length,
        occupied: group.where((t) => t.occupied).length,
      ),
  ]..sort((a, b) => compareDayTime(a.date, a.time, b.date, b.time));
  return slots;
}

/// The parsed page: the occupancy grid plus whatever tournament details the
/// page exposes (name, kind, discipline). Detail fields are null when the
/// page/scraper doesn't provide them — the form then leaves them for the user.
class ScrapeResult {
  const ScrapeResult({
    required this.slots,
    this.name,
    this.kind,
    this.discipline,
  });

  final List<VenueSlot> slots;
  final String? name;
  final TournamentKind? kind;
  final Discipline? discipline;
}

abstract class TournamentScraper {
  /// Human-readable name shown in the UI ("kkmoravskaslavia.cz / mkware").
  String get name;

  /// Downloads and parses the page. Throws on network errors; returns empty
  /// slots when the page has no reservation grid.
  Future<ScrapeResult> fetch(Uri url);
}

class ScraperRegistry {
  /// Returns the scraper able to handle [url], or null → manual entry only.
  static TournamentScraper? forUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return null;
    if (uri.host.endsWith('kkmoravskaslavia.cz') ||
        uri.path.contains('/mkware/')) {
      return MkwareScraper();
    }
    if (uri.host.endsWith('turnajekuzelky.cz')) {
      return TurnajeKuzelkyScraper();
    }
    return null;
  }
}
