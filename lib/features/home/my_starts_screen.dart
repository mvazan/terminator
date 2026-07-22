import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/day_cancel.dart';
import '../../domain/models.dart';
import '../tournaments/tournament_detail_screen.dart';

/// Home screen: the signed-in user's upcoming ordered starts — when, where,
/// with whom. Each start offers "zrušit zájem v tento den": untick my
/// availability everywhere else that day, since I'm already playing here.
class MyStartsScreen extends ConsumerWidget {
  const MyStartsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rosters = ref.watch(rostersProvider).value ?? const [];
    final slots = ref.watch(slotsProvider).value ?? const [];
    final tournaments = ref.watch(tournamentsProvider).value ?? const [];
    final members = ref.watch(membersProvider).value ?? const [];
    final venues = ref.watch(venuesProvider).value ?? const [];
    final venueById = {for (final v in venues) v.id: v};
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
    mine.sort((a, b) => Slot.compare(a.slot, b.slot));

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
                final venue = venueById[start.tournament.venueId];
                final venueName = venue?.name ?? '?';
                final teammates = [
                  for (final r in rosters)
                    if (r.slotId == start.slot.id && r.userId != uid)
                      rosterEntryName(r, members),
                ];
                // The nearest start leads as a hero card with a countdown.
                if (i == 0) {
                  return _heroCard(
                    context,
                    start: start,
                    venueName: venueName,
                    teammates: teammates,
                    inDays: _inDaysLabel(start.slot.date, now),
                    onCancelDay: () =>
                        _cancelDayInterest(context, ref, start.slot),
                  );
                }
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: DateBadge(start.slot.date),
                    title: Text(
                      '${start.slot.time.display()} · '
                      '${start.tournament.timelineLabel(venueName)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text([
                      start.tournament.name,
                      if (teammates.isNotEmpty) 'S: ${teammates.join(', ')}',
                    ].join('\n')),
                    isThreeLine: teammates.isNotEmpty,
                    trailing: IconButton(
                      tooltip: 'Zrušit zájem v tento den',
                      icon: const Icon(Icons.event_busy),
                      onPressed: () =>
                          _cancelDayInterest(context, ref, start.slot),
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

  /// "dnes" / "zítra" / "za 3 dny" / "za 8 dní".
  static String _inDaysLabel(Day date, Day today) {
    final diff = DateTime.utc(date.year, date.month, date.day)
        .difference(DateTime.utc(today.year, today.month, today.day))
        .inDays;
    return switch (diff) {
      0 => 'dnes',
      1 => 'zítra',
      >= 2 && <= 4 => 'za $diff dny',
      _ => 'za $diff dní',
    };
  }

  static Widget _heroCard(BuildContext context,
      {required ({Slot slot, Tournament tournament}) start,
      required String venueName,
      required List<String> teammates,
      required String inDays,
      required VoidCallback onCancelDay}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      color: scheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                TournamentDetailScreen(tournamentId: start.tournament.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nejbližší start · $inDays',
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: scheme.primary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${dayFull(start.slot.date)} '
                      '${start.slot.time.display()}',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(start.tournament.timelineLabel(venueName)),
                    Text(start.tournament.name,
                        style: Theme.of(context).textTheme.bodySmall),
                    if (teammates.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('S: ${teammates.join(', ')}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Zrušit zájem v tento den',
                icon: const Icon(Icons.event_busy),
                onPressed: onCancelDay,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Confirmation first (with the optional ±1 day), then bulk-untick my
  /// availability everywhere else on the chosen day(s). Starts I'm rostered
  /// on are never unticked.
  Future<void> _cancelDayInterest(
      BuildContext context, WidgetRef ref, Slot slot) async {
    final uid = currentUserId;
    if (uid == null) return;

    var neighbors = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Zrušit zájem v tento den?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hraješ ${dayFull(slot.date)} ${slot.time.display()}. '
                'Odhlásí tě to ze všech ostatních zaškrtnutých termínů '
                'v tento den — ve všech turnajích. Starty, na kterých '
                'hraješ, zůstanou.',
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: neighbors,
                onChanged: (v) => setState(() => neighbors = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('I den před a den po'),
                subtitle: const Text('když nechceš hrát 2 dny po sobě'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Zpět'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Odhlásit'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final targets = dayCancelTargets(
      uid: uid,
      day: slot.date,
      includeNeighbors: neighbors,
      slots: ref.read(slotsProvider).value ?? const [],
      availability: ref.read(availabilityProvider).value ?? const [],
      keep: {
        for (final r in ref.read(rostersProvider).value ?? const [])
          if (r.userId == uid) r.slotId,
      },
    );
    if (targets.isEmpty) {
      snack(context, 'Žádné další zaškrtnuté termíny tam nemáš.');
      return;
    }
    await tryAction(
      context,
      () => Api.setAvailabilityBulk(targets, false),
      success: targets.length == 1
          ? 'Odhlášeno z 1 termínu.'
          : 'Odhlášeno ze ${targets.length} termínů.',
    );
  }
}
