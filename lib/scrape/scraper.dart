/// Tournament-page scraping: import the start grid and live occupancy from
/// the organizer's reservation page instead of typing slots by hand.
///
/// A scraper is chosen by URL. Unrecognized URLs get no scraper — the UI then
/// only offers manual slot entry.
library;

import '../domain/models.dart';
import 'galanta.dart';
import 'mkware.dart';
import 'turnajekuzelky.dart';

/// One bookable lane-start scraped from the page.
class VenueTerm {
  const VenueTerm({
    required this.date,
    required this.time,
    required this.occupied,
    this.occupant = '',
  });

  final Day date;
  final HourMinute time;
  final bool occupied;

  /// Raw text of who booked it (name + oddíl/team/klub as the page shows it);
  /// empty for free terms or pages without that info. Matched against our
  /// team's name to tell "full because WE booked it" from foreign bookings.
  final String occupant;
}

/// Occupancy of one start time: how many lanes exist / are already booked,
/// and how many of the booked ones are ours.
class VenueSlot {
  const VenueSlot({
    required this.date,
    required this.time,
    required this.capacity,
    required this.occupied,
    this.occupiedOurs = 0,
  });

  final Day date;
  final HourMinute time;
  final int capacity;
  final int occupied;

  /// Occupied places whose occupant text matched our team (see aggregateTerms).
  final int occupiedOurs;

  int get free => capacity - occupied;
}

/// Groups raw terms into per-(date, time) occupancy.
///
/// [playersPerTerm] scales each term into player places. On mkware one term is
/// one lane (1 player), so the default is 1. On turnajekuzelky a term is a
/// start and the format's "N×" says how many players share it (dvojice → 2), so
/// there the caller passes N — e.g. two free 2× starts at 16:00 become 0/4.
///
/// [ourNeedle] (lowercased team name) marks occupied terms whose occupant
/// contains it as ours; empty = no matching.
List<VenueSlot> aggregateTerms(List<VenueTerm> terms,
    {int playersPerTerm = 1, String ourNeedle = ''}) {
  final needle = ourNeedle.trim().toLowerCase();
  final byKey = <String, List<VenueTerm>>{};
  for (final term in terms) {
    byKey.putIfAbsent('${term.date}|${term.time}', () => []).add(term);
  }
  final slots = [
    for (final group in byKey.values)
      VenueSlot(
        date: group.first.date,
        time: group.first.time,
        capacity: group.length * playersPerTerm,
        occupied: group.where((t) => t.occupied).length * playersPerTerm,
        occupiedOurs: needle.isEmpty
            ? 0
            : group
                    .where((t) =>
                        t.occupied &&
                        t.occupant.toLowerCase().contains(needle))
                    .length *
                playersPerTerm,
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
  /// slots when the page has no reservation grid. [ourTeam] (team name) marks
  /// occupancy booked by us — see VenueSlot.occupiedOurs.
  Future<ScrapeResult> fetch(Uri url, {String ourTeam = ''});
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
    if (uri.host.endsWith('kolky-galanta.sk')) {
      return GalantaScraper();
    }
    return null;
  }
}
