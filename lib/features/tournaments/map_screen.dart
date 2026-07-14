import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/geocoding.dart';
import '../../domain/map_pins.dart';
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

  /// false = all venues, plain pins (upcoming = primary); true = one
  /// tournament per venue, pin colored by my personal state.
  bool _coloredMode = false;

  /// Colored mode only: whether tournaments I've hidden ("nezajímá mě") get a
  /// grey pin. Off by default — hidden means out of sight.
  bool _showHidden = false;

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
      appBar: AppBar(
        title: Text(_coloredMode ? 'Mapa turnajů' : 'Mapa kuželen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Legenda',
            onPressed: _showLegend,
          ),
          if (_coloredMode)
            IconButton(
              icon: Icon(
                  _showHidden ? Icons.visibility : Icons.visibility_off),
              tooltip: _showHidden
                  ? 'Skrýt skryté turnaje'
                  : 'Zobrazit i skryté turnaje',
              onPressed: () => setState(() => _showHidden = !_showHidden),
            ),
          IconButton(
            icon: Icon(_coloredMode ? Icons.location_on : Icons.palette),
            tooltip: _coloredMode
                ? 'Zobrazit všechny kuželny'
                : 'Barevně podle stavu turnaje',
            onPressed: () => setState(() => _coloredMode = !_coloredMode),
          ),
        ],
      ),
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
            markers: _coloredMode
                ? _coloredMarkers(located, now)
                : [
                    for (final venue in located)
                      _pin(
                        venue,
                        color:
                            (upcomingByVenue[venue.id] ?? const []).isNotEmpty
                                ? scheme.primary
                                : scheme.outline,
                        onTap: () => _showVenueSheet(
                            venue, upcomingByVenue[venue.id] ?? const []),
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

  Marker _pin(Venue venue,
          {required Color color, required VoidCallback onTap}) =>
      Marker(
        point: LatLng(venue.lat!, venue.lng!),
        width: 44,
        height: 44,
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: onTap,
          child: Icon(Icons.location_pin, size: 40, color: color),
        ),
      );

  /// Colored mode: one pin per located venue that has a tournament to show,
  /// graded by my personal state (see [VenuePinState]).
  List<Marker> _coloredMarkers(List<Venue> located, Day now) {
    final uid = currentUserId;
    final allSlots = ref.watch(slotsProvider).value ?? const <Slot>[];
    final tournamentOfSlot = {for (final s in allSlots) s.id: s.tournamentId};

    // Tournaments I ticked availability in.
    final myTicked = <String>{};
    if (uid != null) {
      for (final a in ref.watch(availabilityProvider).value ?? const []) {
        if (a.userId != uid) continue;
        final tid = tournamentOfSlot[a.slotId];
        if (tid != null) myTicked.add(tid);
      }
    }

    // Tournaments where I'm rostered on an ordered/confirmed start.
    final myStart = <String>{};
    if (uid != null) {
      final orderSlots = ref.watch(orderSlotsProvider).value ?? const {};
      final orderedSlotIds = <String>{
        for (final o in ref.watch(ordersProvider).value ?? const [])
          if (o.isActive)
            for (final slotId in (orderSlots[o.id] ?? const {}).keys) slotId,
      };
      for (final r in ref.watch(rostersProvider).value ?? const []) {
        if (r.userId == uid && orderedSlotIds.contains(r.slotId)) {
          final tid = tournamentOfSlot[r.slotId];
          if (tid != null) myStart.add(tid);
        }
      }
    }

    final hiddenByMe =
        ref.watch(myHiddenTournamentsProvider).value ?? const <String>{};

    // Pool = live tournaments; drop archived and team-hidden ones entirely.
    // My-hidden ones join only when "show hidden" is on (then they show grey).
    final byVenue = <String, List<Tournament>>{};
    for (final t in ref.watch(allTournamentsProvider).value ?? const []) {
      if (t.isArchived || t.isHidden) continue;
      if (!_showHidden && hiddenByMe.contains(t.id)) continue;
      byVenue.putIfAbsent(t.venueId, () => []).add(t);
    }

    final markers = <Marker>[];
    for (final venue in located) {
      final pin = venuePin(
        venueTournaments: byVenue[venue.id] ?? const [],
        today: now,
        hiddenByMe: hiddenByMe,
        myTicked: myTicked,
        myStart: myStart,
      );
      if (pin == null) continue;
      markers.add(_pin(
        venue,
        color: _pinColor(pin.state),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              TournamentDetailScreen(tournamentId: pin.tournament.id),
        )),
      ));
    }
    return markers;
  }

  static Color _pinColor(VenuePinState s) => switch (s) {
        VenuePinState.hidden => Colors.grey.shade400,
        VenuePinState.past => Colors.grey.shade700,
        VenuePinState.ongoingNone => Colors.green.shade300,
        VenuePinState.ongoingMine => Colors.green.shade600,
        VenuePinState.ongoingStart => Colors.green.shade900,
        VenuePinState.upcomingNone => Colors.orange.shade300,
        VenuePinState.upcomingMine => Colors.orange.shade600,
        VenuePinState.upcomingStart => Colors.orange.shade900,
      };

  /// Legend for whichever view is active — pin colors and what they mean.
  void _showLegend() {
    final scheme = Theme.of(context).colorScheme;
    final (intro, rows) = _coloredMode
        ? (
            'Jedna kuželna = jeden turnaj (probíhající, jinak nejbližší '
                'nadcházející, jinak poslední proběhlý). Barva podle stavu:',
            <(Color, String)>[
              (_pinColor(VenuePinState.ongoingNone), 'Probíhá'),
              (_pinColor(VenuePinState.ongoingMine), 'Probíhá · jsi přihlášen'),
              (_pinColor(VenuePinState.ongoingStart),
                  'Probíhá · máš objednaný start'),
              (_pinColor(VenuePinState.upcomingNone), 'Nadchází'),
              (_pinColor(VenuePinState.upcomingMine),
                  'Nadchází · jsi přihlášen'),
              (_pinColor(VenuePinState.upcomingStart),
                  'Nadchází · máš objednaný start'),
              (_pinColor(VenuePinState.past), 'Proběhlé'),
              if (_showHidden)
                (_pinColor(VenuePinState.hidden), 'Skryté (nezajímá mě)'),
            ],
          )
        : (
            'Všechny kuželny týmu:',
            <(Color, String)>[
              (scheme.primary, 'Má nadcházející turnaj'),
              (scheme.outline, 'Bez nadcházejícího turnaje'),
            ],
          );

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Legenda',
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(intro,
                  style: Theme.of(sheetContext).textTheme.bodyMedium),
              const SizedBox(height: 12),
              for (final (color, label) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.location_pin, size: 28, color: color),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(label,
                            style:
                                Theme.of(sheetContext).textTheme.bodyLarge),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
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
              // Scrollable so many tournaments can't overflow the sheet.
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in upcoming)
                      ListTile(
                        leading: DateBadge(t.startsOn),
                        title: Text(t.name),
                        subtitle: Text(rangeLabel(t.startsOn, t.endsOn)),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TournamentDetailScreen(
                                  tournamentId: t.id),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
