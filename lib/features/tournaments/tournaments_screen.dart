import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import 'timeline_screen.dart';
import 'tournament_detail_screen.dart';
import 'tournament_edit_screen.dart';

class TournamentsScreen extends ConsumerWidget {
  const TournamentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournaments = ref.watch(tournamentsProvider);
    final now = today();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Turnaje'),
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
    final String status;
    if (t.isArchived) {
      status = 'archiv';
    } else if (t.endsOn.isBefore(now)) {
      status = 'odehráno';
    } else if (!t.startsOn.isAfter(now)) {
      status = 'běží';
    } else {
      status = 'za ${t.startsOn.differenceInDays(now)} dní';
    }

    return ListTile(
      title: Text(t.name),
      subtitle: Text(
          '${t.timelineLabel} · ${rangeLabel(t.startsOn, t.endsOn)}'),
      trailing: Chip(label: Text(status)),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TournamentDetailScreen(tournamentId: t.id),
        ),
      ),
    );
  }
}
