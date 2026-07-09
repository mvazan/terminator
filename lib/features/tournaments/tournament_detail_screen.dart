import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/local_prefs.dart';
import '../../data/providers.dart';
import '../../domain/heatmap.dart';
import '../../domain/models.dart';
import '../../scrape/scraper.dart';
import '../chats/chat_screen.dart';
import '../manage/manage_mode.dart';
import 'order_card.dart';
import 'proposal_screen.dart';
import 'slot_cell.dart';
import 'tournament_edit_screen.dart';

class TournamentDetailScreen extends ConsumerStatefulWidget {
  const TournamentDetailScreen({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  ConsumerState<TournamentDetailScreen> createState() =>
      _TournamentDetailScreenState();
}

class _TournamentDetailScreenState
    extends ConsumerState<TournamentDetailScreen> {
  String get tournamentId => widget.tournamentId;
  bool _autoSyncDone = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    // Once per screen visit: refresh venue occupancy from the web when the
    // tournament resolves and the cached data is older than the TTL.
    ref.listenManual(tournamentByIdProvider(widget.tournamentId),
        fireImmediately: true, (_, tournament) {
      if (tournament == null || _autoSyncDone) return;
      if (ScraperRegistry.forUrl(tournament.sourceUrl) != null &&
          Api.scrapeIsStale(tournament)) {
        _autoSyncDone = true;
        _sync(tournament);
      }
    });
  }

  Future<void> _sync(Tournament tournament, {bool manual = false}) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final count = await Api.syncFromWeb(
        tournamentId: tournament.id,
        sourceUrl: tournament.sourceUrl,
      );
      if (manual && mounted) {
        snack(context, 'Obsazenost aktualizována ($count startů).');
      }
    } catch (e) {
      if (manual && mounted) snack(context, 'Synchronizace selhala: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tournament = ref.watch(tournamentByIdProvider(tournamentId));
    if (tournament == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final scrapable = ScraperRegistry.forUrl(tournament.sourceUrl) != null;

    // Fully booked venue slots aren't ours to fill — hide them from the grid.
    final slots = (ref.watch(slotsProvider).value ?? const [])
        .where((s) => s.tournamentId == tournamentId && !s.venueFull)
        .toList()
      ..sort(Slot.compare);
    final slotIds = {for (final s in slots) s.id};
    final availability = (ref.watch(availabilityProvider).value ?? const [])
        .where((a) => slotIds.contains(a.slotId))
        .toList();
    final heatmap = Heatmap.build(
      tournament: tournament,
      slots: slots,
      availability: availability,
    );
    final orders = (ref.watch(ordersProvider).value ?? const [])
        .where((o) => o.tournamentId == tournamentId)
        .toList();
    final members = ref.watch(membersProvider).value ?? const [];
    final showWhoIsIn = ref.watch(showWhoIsInProvider);
    final uid = currentUserId;

    final byDay = slotsByDay(slots);

    final archived = tournament.isArchived;

    final manage = ref.watch(manageUnlockedProvider);
    return Scaffold(
      appBar: AppBar(
        // Long-press the title to reach the hidden manage mode (PIN-gated).
        title: GestureDetector(
          onLongPress: () => handleManageGesture(context, ref),
          child: Text(tournament.name),
        ),
        actions: [
          if (scrapable && !archived)
            IconButton(
              tooltip: 'Aktualizovat obsazenost z webu',
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              onPressed:
                  _syncing ? null : () => _sync(tournament, manual: true),
            ),
          IconButton(
            tooltip: 'Chat k turnaji',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(tournamentId: tournamentId),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (action) => _menuAction(context, action, tournament),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'toggle_who_is_in',
                checked: showWhoIsIn,
                child: const Text('Zobrazit, kdo je přihlášený'),
              ),
              const PopupMenuDivider(),
              if (archived)
                // "New season from last year" — only offered on archived
                // tournaments, where starting a fresh copy makes sense.
                const PopupMenuItem(
                    value: 'duplicate',
                    child: Text('Duplikovat jako nový turnaj'))
              else ...[
                const PopupMenuItem(
                    value: 'edit', child: Text('Upravit turnaj')),
                // Scraped tournaments own their slot grid via the web sync —
                // manual starts don't belong there.
                if (!scrapable)
                  const PopupMenuItem(
                      value: 'add_slot', child: Text('Přidat start')),
                const PopupMenuItem(
                    value: 'archive', child: Text('Archivovat')),
              ],
              if (manage) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                    value: 'hide', child: Text('Skrýt turnaj (s chaty)')),
              ],
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (archived)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.archive_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Turnaj je archivovaný — jen ke čtení. Nedají se '
                        'měnit termíny, hlasovat ani objednávat.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          _InfoCard(
            tournament: tournament,
            venue: ref.watch(venueByIdProvider(tournament.venueId)),
          ),
          const SizedBox(height: 12),
          if (!archived) ...[
            _BestPicksCard(tournament: tournament, heatmap: heatmap),
            const SizedBox(height: 16),
          ],
          Text('Kdy můžeš? Odklikni si starty:',
              style: Theme.of(context).textTheme.titleMedium),
          Text(
            scrapable
                ? 'Číslo „nás/dráhy" = kolik z nás může / kolik je volných drah.'
                : 'Číslo = kolik nás může.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final day in byDay.keys)
            _DayRow(
              day: day,
              slots: byDay[day]!,
              heatmap: heatmap,
              members: members,
              uid: uid,
              readOnly: archived,
            ),
          const SizedBox(height: 16),
          if (orders.any((o) => o.status != OrderStatus.cancelled)) ...[
            Text('Návrhy a objednávky',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final order in orders)
              if (order.status != OrderStatus.cancelled)
                OrderCard(
                  order: order,
                  tournament: tournament,
                  readOnly: archived,
                ),
          ],
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Future<void> _menuAction(
      BuildContext context, String action, Tournament tournament) async {
    switch (action) {
      case 'toggle_who_is_in':
        await ref.read(showWhoIsInProvider.notifier).toggle();
      case 'duplicate':
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                TournamentEditScreen(duplicateFrom: tournament)));
      case 'edit':
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TournamentEditScreen(existing: tournament)));
      case 'add_slot':
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 30)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date == null || !context.mounted) return;
        final time = await showTimePicker(
            context: context,
            initialTime: const TimeOfDay(hour: 17, minute: 0));
        if (time == null || !context.mounted) return;
        await tryAction(
          context,
          () => Api.addSlot(tournament.id, Day.fromDateTime(date),
              HourMinute(time.hour, time.minute)),
          success: 'Start přidán.',
        );
      case 'archive':
        final confirmed = await confirmDialog(
          context,
          title: 'Archivovat turnaj?',
          message: '„${tournament.name}" se přesune do archivu a stane se '
              'jen ke čtení — nepůjde upravovat, přidávat termíny, hlasovat '
              'ani objednávat.',
          confirmLabel: 'Archivovat',
        );
        if (!confirmed || !context.mounted) return;
        await tryAction(context, () => Api.archiveTournament(tournament.id),
            success: 'Turnaj archivován.');
        if (context.mounted) Navigator.of(context).pop();
      case 'hide':
        final confirmed = await confirmDialog(
          context,
          title: 'Skrýt turnaj?',
          message: '„${tournament.name}" i s chaty zmizí ze seznamu. '
              'Nic se nesmaže — skrytí jde vrátit v seznamu turnajů '
              'v režimu správy.',
          confirmLabel: 'Skrýt',
        );
        if (!confirmed || !context.mounted) return;
        await tryAction(
            context, () => Api.setTournamentHidden(tournament.id, true),
            success: 'Turnaj skryt.');
        if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.tournament, this.venue});

  final Tournament tournament;
  final Venue? venue;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final address = venue?.address ?? '';
    final contacts = <Widget>[
      if (address.isNotEmpty)
        ActionChip(
          avatar: const Icon(Icons.directions_outlined, size: 16),
          label: const Text('navigovat'),
          onPressed: () => launchMap(address),
        ),
      if (t.contactEmail.isNotEmpty)
        ActionChip(
          avatar: const Icon(Icons.mail_outline, size: 16),
          label: Text(t.contactEmail),
          onPressed: () => launchEmail(t.contactEmail),
        ),
      if (t.contactPhone.isNotEmpty)
        ActionChip(
          avatar: const Icon(Icons.phone_outlined, size: 16),
          label: Text(t.contactPhone),
          onPressed: () => launchPhone(t.contactPhone),
        ),
      if (t.sourceUrl.isNotEmpty)
        ActionChip(
          avatar: const Icon(Icons.language, size: 16),
          label: const Text('web turnaje'),
          onPressed: () => launchWeb(t.sourceUrl),
        ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${t.timelineLabel(venue?.name ?? '?')} · '
                '${rangeLabel(t.startsOn, t.endsOn)}'),
            if (address.isNotEmpty)
              Text(address, style: Theme.of(context).textTheme.bodySmall),
            if (t.scrapedAt != null)
              Text(
                'Obsazenost z webu: ${_freshness(t.scrapedAt!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (contacts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 8, runSpacing: 4, children: contacts),
              ),
            if (t.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t.notes,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }

  String _freshness(DateTime scrapedAt) {
    final age = DateTime.now().toUtc().difference(scrapedAt.toUtc());
    if (age.inMinutes < 1) return 'právě teď';
    if (age.inMinutes < 60) return 'před ${age.inMinutes} min';
    if (age.inHours < 24) return 'před ${age.inHours} h';
    return 'před ${age.inDays} dny';
  }

}

class _DayRow extends ConsumerWidget {
  const _DayRow({
    required this.day,
    required this.slots,
    required this.heatmap,
    required this.members,
    required this.uid,
    this.readOnly = false,
  });

  final Day day;
  final List<Slot> slots;
  final Heatmap heatmap;
  final List<Profile> members;
  final String? uid;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayStats = heatmap.byDay[day];
    final showWhoIsIn = ref.watch(showWhoIsInProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(dayLabel(day),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 8),
              if (dayStats != null && dayStats.distinctPlayers > 0)
                Text('${dayStats.distinctPlayers} lidí může',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final slot in slots) _cell(context, slot)],
          ),
          if (showWhoIsIn) _whoIsIn(context),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, Slot slot) {
    final stats = heatmap.bySlotId[slot.id];
    final mine = uid != null && (stats?.userIds.contains(uid) ?? false);

    return SlotCell(
      time: slot.time,
      count: stats?.count ?? 0,
      intensity: heatmap.intensity(slot.id),
      isOrderable: stats?.isOrderable ?? false,
      mine: mine,
      venueFree: slot.venueFree,
      onTap: readOnly ? null : () => Api.setAvailability(slot.id, !mine),
      // Scraped slots are owned by the web sync — no manual deletion.
      onLongPress: readOnly || slot.hasVenueInfo
          ? null
          : () => _confirmDelete(context, slot),
    );
  }

  /// Names of who ticked each start that day, listed under the day's grid
  /// (shown when the team-wide "who's in" toggle is on).
  Widget _whoIsIn(BuildContext context) {
    final lines = <Widget>[];
    for (final slot in slots) {
      final ids = heatmap.bySlotId[slot.id]?.userIds ?? const <String>{};
      if (ids.isEmpty) continue;
      final names = (ids.map((id) => memberName(members, id)).toList()
            ..sort())
          .join(', ');
      lines.add(RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall,
          children: [
            TextSpan(
              text: '${slot.time.display()}: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: names),
          ],
        ),
      ));
    }
    if (lines.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: line,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Slot slot) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Smazat start?',
      message: '${dayFull(slot.date)} ${slot.time.display()} — '
          'včetně hlasů a obsazení.',
      confirmLabel: 'Smazat',
      cancelLabel: 'Ne',
    );
    if (confirmed && context.mounted) {
      await tryAction(context, () => Api.deleteSlot(slot.id));
    }
  }
}

class _BestPicksCard extends StatelessWidget {
  const _BestPicksCard({required this.tournament, required this.heatmap});

  final Tournament tournament;
  final Heatmap heatmap;

  @override
  Widget build(BuildContext context) {
    final picks = bestPicks(heatmap: heatmap);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nejsilnější termíny',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (picks.isEmpty)
              const Text('Zatím se nikde nesešlo dost hráčů. '
                  'Odklikejte si termíny!')
            else
              for (final p in picks)
                Text('• ${dayLabel(p.slot.date)} ${p.slot.time.display()} — '
                    '${p.count} hráčů'),
            const SizedBox(height: 12),
            // Voting ("Hlasování") is hidden for now — its role is being
            // reconsidered. Direct ordering stays.
            FilledButton.icon(
              icon: const Icon(Icons.receipt_long),
              label: const Text('Zadat objednávku'),
              onPressed: () => _openProposal(context, direct: true),
            ),
          ],
        ),
      ),
    );
  }

  void _openProposal(BuildContext context, {required bool direct}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProposalScreen(
        tournament: tournament,
        preselected: {for (final s in suggestedBundle(heatmap)) s.slot.id},
        directlyOrdered: direct,
      ),
    ));
  }
}
