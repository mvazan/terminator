import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/geocoding.dart';
import '../../domain/models.dart';
import 'tournament_detail_screen.dart';

/// Map of the team's bowling alleys (OSM tiles). Pins are primary-colored
/// when the venue has upcoming tournaments; tapping one opens a sheet with
/// the venue's tournaments and dates. Venues saved before coordinates existed
/// are geocoded lazily here, one per second per Nominatim's policy.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  /// Venue ids geocoding failed for this session — don't re-hit Nominatim.
  final _geocodeFailed = <String>{};
  bool _backfilling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _backfillCoords());
  }

  /// Geocodes venues that have an address but no coordinates yet and stores
  /// the result — markers pop in live via the venues stream.
  Future<void> _backfillCoords() async {
    if (_backfilling) return;
    _backfilling = true;
    try {
      final pending = (ref.read(venuesProvider).value ?? const <Venue>[])
          .where((v) =>
              !v.hasCoords &&
              v.address.trim().isNotEmpty &&
              !_geocodeFailed.contains(v.id))
          .toList();
      for (final venue in pending) {
        if (!mounted) return;
        final coords = await geocodeAddress(venue.address);
        if (coords == null) {
          _geocodeFailed.add(venue.id);
          continue;
        }
        try {
          await Api.updateVenue(
              venue.id, {'lat': coords.lat, 'lng': coords.lng});
        } catch (_) {
          _geocodeFailed.add(venue.id);
        }
      }
    } finally {
      _backfilling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final venues = ref.watch(venuesProvider).value ?? const <Venue>[];
    final tournaments = ref.watch(tournamentsProvider).value ?? const [];
    final now = today();

    // Upcoming (incl. running) tournaments per venue.
    final upcomingByVenue = <String, List<Tournament>>{};
    for (final t in tournaments) {
      if (t.isArchived || t.endsOn.isBefore(now)) continue;
      upcomingByVenue.putIfAbsent(t.venueId, () => []).add(t);
    }

    final located = venues.where((v) => v.hasCoords).toList();
    final points = [
      for (final v in located) LatLng(v.lat!, v.lng!),
    ];

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Mapa kuželen')),
      body: FlutterMap(
        options: MapOptions(
          initialCameraFit: points.length >= 2
              ? CameraFit.coordinates(
                  coordinates: points,
                  padding: const EdgeInsets.all(48),
                )
              : null,
          initialCenter:
              points.length == 1 ? points.single : const LatLng(49.8, 15.5),
          initialZoom: points.length == 1 ? 12 : 7,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'cz.kuzelky.terminator',
          ),
          MarkerLayer(
            markers: [
              for (final venue in located)
                Marker(
                  point: LatLng(venue.lat!, venue.lng!),
                  width: 44,
                  height: 44,
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    onTap: () => _showVenueSheet(
                        venue, upcomingByVenue[venue.id] ?? const []),
                    child: Icon(
                      Icons.location_pin,
                      size: 40,
                      color: (upcomingByVenue[venue.id] ?? const []).isNotEmpty
                          ? scheme.primary
                          : scheme.outline,
                    ),
                  ),
                ),
            ],
          ),
          // OSM tile usage policy requires visible attribution.
          const SimpleAttributionWidget(
            source: Text('OpenStreetMap contributors'),
          ),
        ],
      ),
    );
  }

  void _showVenueSheet(Venue venue, List<Tournament> upcoming) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(venue.name,
                      style: Theme.of(sheetContext).textTheme.titleLarge),
                  Text(
                    [
                      lanesLabel(venue.laneCount),
                      if (venue.address.isNotEmpty) venue.address,
                    ].join(' · '),
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (upcoming.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text('Žádný nadcházející turnaj.'),
              )
            else
              for (final t in upcoming)
                ListTile(
                  leading: DateBadge(t.startsOn),
                  title: Text(t.name),
                  subtitle: Text(rangeLabel(t.startsOn, t.endsOn)),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            TournamentDetailScreen(tournamentId: t.id),
                      ),
                    );
                  },
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
