import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import '../manage/manage_mode.dart';
import 'timeline_screen.dart';
import 'tournament_detail_screen.dart';
import 'tournament_edit_screen.dart';

class TournamentsScreen extends ConsumerWidget {
  const TournamentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournaments = ref.watch(tournamentsProvider);
    final now = today();
    final manage = ref.watch(manageUnlockedProvider);
    final hidden = manage
        ? (ref.watch(allTournamentsProvider).value ?? const [])
            .where((t) => t.isHidden)
            .toList()
        : const <Tournament>[];

    return Scaffold(
      appBar: AppBar(
        // Long-press the title to reach the hidden manage mode (PIN-gated).
        title: GestureDetector(
          onLongPress: () => handleManageGesture(context, ref),
          child: const Text('Turnaje'),
        ),
        actions: [
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
        data: (all) {
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

          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final t in active) _TournamentTile(tournament: t, now: now),
              if (past.isNotEmpty)
                ExpansionTile(
                  title: Text('Odehrané a archivované (${past.length})'),
                  children: [
                    for (final t in past)
                      _TournamentTile(tournament: t, now: now),
                  ],
                ),
              if (hidden.isNotEmpty)
                ExpansionTile(
                  leading: const Icon(Icons.visibility_off_outlined),
                  title: Text('Skryté (${hidden.length})'),
                  children: [
                    for (final t in hidden)
                      ListTile(
                        leading: const Icon(Icons.visibility_off, size: 20),
                        title: Text(t.name),
                        subtitle: Text(t.timelineLabel),
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
  const _TournamentTile({required this.tournament, required this.now});

  final Tournament tournament;
  final Day now;

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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: ListTile(
        leading: DateBadge(t.startsOn),
        title: Text(t.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '${t.timelineLabel} · ${rangeLabel(t.startsOn, t.endsOn)}'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TournamentDetailScreen(tournamentId: t.id),
          ),
        ),
      ),
    );
  }
}
