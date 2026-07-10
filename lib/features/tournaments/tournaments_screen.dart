import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import '../../scrape/scraper.dart';
import '../manage/manage_mode.dart';
import 'timeline_screen.dart';
import 'tournament_detail_screen.dart';
import 'tournament_edit_screen.dart';

class TournamentsScreen extends ConsumerStatefulWidget {
  const TournamentsScreen({super.key});

  @override
  ConsumerState<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends ConsumerState<TournamentsScreen> {
  /// Eye mode: show also the tournaments I hid, each with a checkbox to
  /// hide/unhide in bulk. Off = hidden ones simply disappear.
  bool _showHidden = false;

  @override
  Widget build(BuildContext context) {
    final tournaments = ref.watch(tournamentsProvider);
    final venueNames = ref.watch(venueNamesProvider);
    final now = today();
    final manage = ref.watch(manageUnlockedProvider);
    final hidden = manage
        ? (ref.watch(allTournamentsProvider).value ?? const [])
            .where((t) => t.isHidden)
            .toList()
        : const <Tournament>[];
    // Tournaments the current user hid for themselves ("not interested").
    final myHiddenIds = ref.watch(myHiddenTournamentsProvider).value ??
        const <String>{};

    return Scaffold(
      appBar: AppBar(
        // Long-press the title to reach the hidden manage mode (PIN-gated).
        title: GestureDetector(
          onLongPress: () => handleManageGesture(context, ref),
          child: const Text('Turnaje'),
        ),
        actions: [
          // Eye mode: reveal my hidden tournaments with checkboxes to
          // hide/unhide in bulk; off = hidden ones disappear again.
          IconButton(
            tooltip: _showHidden
                ? 'Skrýt odškrtnuté turnaje'
                : 'Zobrazit skryté turnaje',
            icon: Icon(_showHidden
                ? Icons.visibility
                : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _showHidden = !_showHidden),
          ),
          IconButton(
            tooltip: 'Sezónní kalendář',
            icon: const Icon(Icons.calendar_view_week),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TimelineScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TournamentEditScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Nový turnaj'),
      ),
      body: tournaments.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Chyba: $e')),
        data: (visible) {
          // Eye mode shows also the tournaments I hid; team-hidden stay out.
          final all = _showHidden
              ? [
                  for (final t in (ref.watch(allTournamentsProvider).value ??
                      const <Tournament>[]))
                    if (!t.isHidden) t,
                ]
              : visible;
          final active = [
            for (final t in all)
              if (!t.isArchived && !t.endsOn.isBefore(now)) t,
          ];
          final past = [
            for (final t in all)
              if (t.isArchived || t.endsOn.isBefore(now)) t,
          ]..sort((a, b) => b.endsOn.compareTo(a.endsOn));

          if (all.isEmpty) {
            return const Center(
              child: Text('Zatím žádný turnaj.\nZalož první!',
                  textAlign: TextAlign.center),
            );
          }

          Widget tile(Tournament t) => _TournamentTile(
                tournament: t,
                now: now,
                venueName: venueNames[t.venueId] ?? '?',
                hiddenByMe:
                    _showHidden ? myHiddenIds.contains(t.id) : null,
              );

          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final t in active) tile(t),
              if (past.isNotEmpty)
                ExpansionTile(
                  title: Text('Odehrané a archivované (${past.length})'),
                  children: [for (final t in past) tile(t)],
                ),
              if (hidden.isNotEmpty)
                ExpansionTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: Text('Skryté pro tým (${hidden.length})'),
                  children: [
                    for (final t in hidden)
                      ListTile(
                        leading: const Icon(Icons.visibility_off, size: 20),
                        title: Text(t.name),
                        subtitle: Text(t.timelineLabel(venueNames[t.venueId] ?? '?')),
                        trailing: TextButton(
                          onPressed: () => tryAction(context,
                              () => Api.setTournamentHidden(t.id, false),
                              success: 'Turnaj zobrazen.'),
                          child: const Text('Zobrazit'),
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TournamentTile extends StatelessWidget {
  const _TournamentTile({
    required this.tournament,
    required this.now,
    required this.venueName,
    this.hiddenByMe,
  });

  final Tournament tournament;
  final Day now;
  final String venueName;

  /// Non-null = eye mode: show a checkbox (checked = visible for me) and dim
  /// the tile when hidden. Null = normal browsing, no checkbox.
  final bool? hiddenByMe;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final scheme = Theme.of(context).colorScheme;
    final String status;
    Color chipColor = scheme.surfaceContainerHighest;
    Color chipText = scheme.onSurfaceVariant;
    if (t.isArchived) {
      status = 'archiv';
    } else if (t.endsOn.isBefore(now)) {
      status = 'odehráno';
    } else if (!t.startsOn.isAfter(now)) {
      status = 'běží';
      chipColor = scheme.primaryContainer;
      chipText = scheme.onPrimaryContainer;
    } else {
      status = 'za ${t.startsOn.differenceInDays(now)} dní';
      chipColor = scheme.secondaryContainer;
      chipText = scheme.onSecondaryContainer;
    }

    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: DateBadge(t.startsOn),
        title: Text(t.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${t.timelineLabel(venueName)} · ${rangeLabel(t.startsOn, t.endsOn)}'),
        // Eye mode swaps the status column for a checkbox: checked = visible
        // for me, unchecked = hidden (list + chat + notifications, me only).
        trailing: hiddenByMe != null
            ? Checkbox(
                value: !hiddenByMe!,
                onChanged: (v) => tryAction(
                    context,
                    () =>
                        Api.setTournamentHiddenForMe(t.id, v != true)),
              )
            : SizedBox(
                height: 48,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Tournaments whose starts/occupancy sync from a
                    // recognized web page get a small globe marker in the
                    // top-right corner.
                    if (ScraperRegistry.forUrl(t.sourceUrl) != null)
                      Tooltip(
                        message: 'Synchronizováno z webu',
                        child: Icon(Icons.public,
                            size: 16, color: scheme.outline),
                      )
                    else
                      const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: chipColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(status,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: chipText)),
                    ),
                  ],
                ),
              ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TournamentDetailScreen(tournamentId: t.id),
          ),
        ),
      ),
    );
    // Hidden ones are dimmed while revealed in eye mode.
    return hiddenByMe == true ? Opacity(opacity: 0.5, child: card) : card;
  }
}
