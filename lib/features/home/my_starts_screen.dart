import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import '../tournaments/tournament_detail_screen.dart';

/// Home screen: the signed-in user's upcoming ordered starts — when, where,
/// with whom — plus one-tap "add to phone calendar".
class MyStartsScreen extends ConsumerWidget {
  const MyStartsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rosters = ref.watch(rostersProvider).value ?? const [];
    final slots = ref.watch(slotsProvider).value ?? const [];
    final tournaments = ref.watch(tournamentsProvider).value ?? const [];
    final members = ref.watch(membersProvider).value ?? const [];
    final uid = currentUserId;

    final slotById = {for (final s in slots) s.id: s};
    final tournamentById = {for (final t in tournaments) t.id: t};
    final now = today();

    final mine = <({Slot slot, Tournament tournament})>[];
    for (final r in rosters) {
      if (r.userId != uid) continue;
      final slot = slotById[r.slotId];
      if (slot == null || slot.date.isBefore(now)) continue;
      final tournament = tournamentById[slot.tournamentId];
      if (tournament == null) continue;
      mine.add((slot: slot, tournament: tournament));
    }
    mine.sort((a, b) {
      final byDate = a.slot.date.compareTo(b.slot.date);
      if (byDate != 0) return byDate;
      return a.slot.time.compareTo(b.slot.time);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Moje starty')),
      body: mine.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Zatím nikde nehraješ.\n\n'
                  'Mrkni do Turnajů, odklikej si termíny,\n'
                  'a až se objedná, uvidíš tady své starty.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              itemCount: mine.length,
              itemBuilder: (context, i) {
                final start = mine[i];
                final teammates = [
                  for (final r in rosters)
                    if (r.slotId == start.slot.id && r.userId != uid)
                      rosterEntryName(r, members),
                ];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    title: Text(
                      '${dayLabel(start.slot.date)} '
                      '${start.slot.time.display()} — '
                      '${start.tournament.timelineLabel}',
                    ),
                    subtitle: Text([
                      start.tournament.name,
                      if (teammates.isNotEmpty) 'S: ${teammates.join(', ')}',
                    ].join('\n')),
                    isThreeLine: teammates.isNotEmpty,
                    trailing: IconButton(
                      tooltip: 'Přidat do kalendáře',
                      icon: const Icon(Icons.event_available),
                      onPressed: () => _addToCalendar(context, start),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TournamentDetailScreen(
                            tournamentId: start.tournament.id),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _addToCalendar(
      BuildContext context, ({Slot slot, Tournament tournament}) start) {
    final d = start.slot.date;
    final t = start.slot.time;
    final begin = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    Add2Calendar.addEvent2Cal(Event(
      title: 'Kuželky: ${start.tournament.name}',
      description: 'Start ${t.display()} — ${start.tournament.timelineLabel}',
      location: start.tournament.venue,
      startDate: begin,
      endDate: begin.add(const Duration(hours: 2)),
    ));
  }
}
