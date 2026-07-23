import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/local_prefs.dart';
import '../../data/providers.dart';
import '../../domain/commitments.dart';
import '../../domain/heatmap.dart';
import '../../domain/models.dart';
import '../../domain/who_is_in.dart';
import '../../scrape/scraper.dart';
import '../chats/chat_screen.dart';
import '../manage/manage_mode.dart';
import 'order_card.dart';
import 'proposal_screen.dart';
import 'slot_cell.dart';
import 'tournament_edit_screen.dart';

class TournamentDetailScreen extends ConsumerStatefulWidget {
  const TournamentDetailScreen(
      {super.key, required this.tournamentId, this.scrollToOrders = false});

  final String tournamentId;

  /// Open with the "Návrhy a objednávky" section in view (day-chat bar tap).
  final bool scrollToOrders;

  @override
  ConsumerState<TournamentDetailScreen> createState() =>
      _TournamentDetailScreenState();
}

class _TournamentDetailScreenState
    extends ConsumerState<TournamentDetailScreen> {
  String get tournamentId => widget.tournamentId;
  bool _autoSyncDone = false;
  bool _syncing = false;
  final _ordersKey = GlobalKey();
  bool _scrolledToOrders = false;

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

  /// Smooth-scrolls to the "Objednávky" section (green chip / day-chat bar).
  void _scrollToOrders() {
    final ctx = _ordersKey.currentContext;
    if (ctx != null && mounted) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300), alignment: 0.05);
    }
  }

  Future<void> _sync(Tournament tournament, {bool manual = false}) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final count = await Api.syncFromWeb(
        tournamentId: tournament.id,
        sourceUrl: tournament.sourceUrl,
        ourTeam: ref.read(myTeamProvider)?.name ?? '',
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

    final archived = tournament.isArchived;
    // A finished tournament is history: show every day read-only so people can
    // still see who was signed up where. A running one hides its already-past
    // days — you can't sign up for them anymore, so they'd only be clutter.
    final now = today();
    final ended = archived || tournament.endsOn.isBefore(now);

    final orders = (ref.watch(ordersProvider).value ?? const [])
        .where((o) => o.tournamentId == tournamentId)
        .toList();
    // Ordered lanes per slot (active orders only) and assigned players per
    // slot — the grid shows an ordered start as "assigned/lanes" in green.
    final activeOrderIds = {
      for (final o in orders)
        if (o.isActive) o.id,
    };
    final orderSlots = ref.watch(orderSlotsProvider).value ?? const {};
    final orderedLanesBySlot = <String, int>{};
    for (final entry in orderSlots.entries) {
      if (!activeOrderIds.contains(entry.key)) continue;
      for (final se in entry.value.entries) {
        orderedLanesBySlot[se.key] = (orderedLanesBySlot[se.key] ?? 0) + se.value;
      }
    }
    // Roster entry count per slot (guests included) — feeds the green chips.
    // Interest suppression of assigned users is handled globally by
    // effectiveAvailabilityProvider, so no per-slot subtraction here.
    final assignedBySlot = <String, int>{};
    for (final r in ref.watch(rostersProvider).value ?? const <RosterEntry>[]) {
      assignedBySlot[r.slotId] = (assignedBySlot[r.slotId] ?? 0) + 1;
    }

    final allSlots = (ref.watch(slotsProvider).value ?? const <Slot>[])
        .where((s) => s.tournamentId == tournamentId)
        .toList()
      ..sort(Slot.compare);
    // The grid collects interest, so it shows only starts with free lanes —
    // full ones (foreign or ours) are hidden. Ordered starts live in the
    // green chips + the Objednávky section instead. History keeps everything.
    final slots = [
      for (final s in allSlots)
        if (ended || !s.venueFull) s,
    ];
    // Ordered starts per day (from ALL slots — a fully booked ordered start
    // isn't in the grid anymore): the day's green chips.
    final orderedChipsByDay =
        <Day, List<({HourMinute time, int lanes, int players})>>{};
    for (final s in allSlots) {
      final lanes = orderedLanesBySlot[s.id] ?? 0;
      if (lanes == 0) continue;
      orderedChipsByDay.putIfAbsent(s.date, () => []).add(
          (time: s.time, lanes: lanes, players: assignedBySlot[s.id] ?? 0));
    }
    for (final chips in orderedChipsByDay.values) {
      chips.sort((a, b) => a.time.compareTo(b.time));
    }
    final slotIds = {for (final s in slots) s.id};
    // Effective (not raw): a player committed to a start that day no longer
    // counts as "interested" on any other slot that day.
    final availability = ref.watch(effectiveAvailabilityProvider)
        .where((a) => slotIds.contains(a.slotId))
        .toList();
    final heatmap = Heatmap.build(
      tournament: tournament,
      slots: slots,
      availability: availability,
    );
    final members = ref.watch(membersProvider).value ?? const [];
    final showWhoIsIn = ref.watch(showWhoIsInProvider);
    final uid = currentUserId;

    final byDay = slotsByDay(slots);
    // A tournament I've hidden ("nezajímá mě") is view-only — no signing up.
    final hiddenByMe = ref
            .watch(myHiddenTournamentsProvider)
            .value
            ?.contains(tournamentId) ??
        false;
    final readOnly = ended || hiddenByMe;
    // A day can have chips but no free starts — it still gets its row.
    final dayKeys = {...byDay.keys, ...orderedChipsByDay.keys}.toList()..sort();
    final visibleDays = [
      for (final day in dayKeys)
        if (ended || !day.isBefore(now)) day,
    ];

    final manage = ref.watch(manageUnlockedProvider);
    final venueName =
        ref.watch(venueByIdProvider(tournament.venueId))?.name ?? '?';

    // Days I'm already committed to play (here or elsewhere) are read-only
    // for me — my interest that day is settled by the order. The hint names
    // the venue(s) so my vanished ticks make sense.
    final myCommitted = uid == null
        ? const <Commitment>[]
        : [for (final c in ref.watch(commitmentsProvider)) if (c.userId == uid) c];
    final venueNames = ref.watch(venueNamesProvider);
    final lockedVenuesByDay = <Day, String>{};
    if (!readOnly) {
      final byDayVenues = <Day, List<String>>{};
      for (final c in myCommitted) {
        final t = ref.watch(tournamentByIdProvider(c.tournamentId));
        final name = t == null ? '?' : (venueNames[t.venueId] ?? '?');
        (byDayVenues[c.day] ??= []).add(name);
      }
      for (final e in byDayVenues.entries) {
        lockedVenuesByDay[e.key] = e.value.toSet().join(', ');
      }
    }

    // Opened from a day chat's context bar: bring the orders into view once
    // they're actually built (data may land a frame or two later).
    if (widget.scrollToOrders && !_scrolledToOrders && orders.isNotEmpty) {
      _scrolledToOrders = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToOrders());
    }
    return Scaffold(
      appBar: AppBar(
        // Long-press the title to reach the hidden manage mode (PIN-gated).
        // Venue leads (the team thinks in alleys); the tournament's own name
        // rides below in small type.
        title: ManageGestureTitle(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(venueName, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                tournament.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
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
              const PopupMenuDivider(),
              if (hiddenByMe)
                const PopupMenuItem(
                    value: 'unhide_for_me', child: Text('Zrušit skrytí'))
              else
                const PopupMenuItem(
                    value: 'hide_for_me',
                    child: Text('Skrýt (nezajímá mě)')),
              if (manage) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                    value: 'hide', child: Text('Skrýt pro celý tým (s chaty)')),
              ],
            ],
          ),
        ],
      ),
      // Non-lazy on purpose: the content is small, and "open scrolled to the
      // orders" (day-chat bar) needs the whole body laid out so
      // ensureVisible has a context to scroll to.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          if (archived || hiddenByMe)
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
                    Icon(
                        archived
                            ? Icons.archive_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        archived
                            ? 'Turnaj je archivovaný — jen ke čtení. Nedají se '
                                'měnit termíny, hlasovat ani objednávat.'
                            : 'Tento turnaj máš skrytý — jen k nahlédnutí, '
                                'přihlašování je vypnuté. Vrátit to jde '
                                'v menu („Zrušit skrytí").',
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
          // "Nejsilnější termíny" only once someone can actually play; the
          // order button stays reachable either way.
          if (!readOnly && bestPicks(heatmap: heatmap).isNotEmpty) ...[
            _BestPicksCard(
                tournament: tournament,
                heatmap: heatmap,
                orderedLanesBySlot: orderedLanesBySlot),
            const SizedBox(height: 12),
          ] else if (!readOnly) ...[
            FilledButton.icon(
              icon: const Icon(Icons.receipt_long),
              label: const Text('Zadat objednávku'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ProposalScreen(
                  tournament: tournament,
                  directlyOrdered: true,
                ),
              )),
            ),
            const SizedBox(height: 12),
          ],
          if (orders.any((o) => o.status != OrderStatus.cancelled)) ...[
            Text('Objednávky',
                key: _ordersKey,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final order in orders)
              if (order.status != OrderStatus.cancelled)
                OrderCard(
                  order: order,
                  tournament: tournament,
                  readOnly: readOnly,
                ),
            const SizedBox(height: 12),
          ],
          Text(
              readOnly
                  ? (ended ? 'Kdo byl přihlášený:' : 'Kdo je přihlášený:')
                  : 'Kdy můžeš? Odklikni si starty:',
              style: Theme.of(context).textTheme.titleMedium),
          if (!readOnly) ...[
            Text(
              scrapable
                  ? 'Číslo „nás/dráhy" = kolik z nás může / kolik je volných drah.'
                  : 'Číslo = kolik nás může.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              '✓ = dost lidí na objednání · zvýrazněný rámeček = tvoje volba',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (scrapable)
              Text(
                '⌂ = obsazeno námi (naše rezervace)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Text(
              'zelený štítek = objednaný start (klepnutím otevřeš detaily)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          for (final day in visibleDays)
            _DayRow(
              day: day,
              slots: byDay[day] ?? const [],
              heatmap: heatmap,
              members: members,
              uid: uid,
              readOnly: readOnly,
              orderedChips: orderedChipsByDay[day] ?? const [],
              onOrderedTap: _scrollToOrders,
              lockedVenues: lockedVenuesByDay[day],
            ),
          const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  /// How many slots of [tournamentId] the current user has ticked — feeds the
  /// "hiding clears your ticks" warning.
  int _myTickCount(String tournamentId) {
    final uid = currentUserId;
    if (uid == null) return 0;
    final slotIds = {
      for (final s in ref.read(slotsProvider).value ?? const <Slot>[])
        if (s.tournamentId == tournamentId) s.id,
    };
    return (ref.read(availabilityProvider).value ?? const [])
        .where((a) => a.userId == uid && slotIds.contains(a.slotId))
        .length;
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
              'ani objednávat. K názvu se doplní rok, aby se příští ročník '
              'nepletl.',
          confirmLabel: 'Archivovat',
        );
        if (!confirmed || !context.mounted) return;
        await tryAction(context, () => Api.archiveTournament(tournament),
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
      case 'hide_for_me':
        // Hiding also clears my ticks — warn when there are any to lose.
        final myTicks = _myTickCount(tournament.id);
        final tickWarning = switch (myTicks) {
          0 => '',
          1 => '\n\nZruší se i tvůj zaškrtnutý termín.',
          >= 2 && <= 4 => '\n\nZruší se i tvoje $myTicks zaškrtnuté termíny.',
          _ => '\n\nZruší se i tvých $myTicks zaškrtnutých termínů.',
        };
        final confirmed = await confirmDialog(
          context,
          title: 'Skrýt turnaj?',
          message: '„${tournament.name}" zmizí z tvého seznamu a chatů a '
              'nebudeš k němu dostávat upozornění. Ostatních se to netýká. '
              'Vrátit to jde v seznamu turnajů.$tickWarning',
          confirmLabel: 'Skrýt',
        );
        if (!confirmed || !context.mounted) return;
        await tryAction(
            context, () => Api.setTournamentHiddenForMe(tournament.id, true),
            success: 'Turnaj skryt (jen pro tebe).');
        if (context.mounted) Navigator.of(context).pop();
      case 'unhide_for_me':
        await tryAction(
            context, () => Api.setTournamentHiddenForMe(tournament.id, false),
            success: 'Skrytí zrušeno.');
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

class _DayRow extends ConsumerStatefulWidget {
  const _DayRow({
    required this.day,
    required this.slots,
    required this.heatmap,
    required this.members,
    required this.uid,
    this.readOnly = false,
    this.orderedChips = const [],
    this.onOrderedTap,
    this.lockedVenues,
  });

  final Day day;
  final List<Slot> slots;
  final Heatmap heatmap;
  final List<Profile> members;
  final String? uid;
  final bool readOnly;

  /// This day's ordered starts — rendered as green chips above the cells;
  /// tapping one jumps to the Objednávky section.
  final List<({HourMinute time, int lanes, int players})> orderedChips;
  final VoidCallback? onOrderedTap;

  /// Non-null when I'm already committed to play this day: the venue name(s)
  /// ("Vracov" / "Vracov, Bratislava"). The day is then read-only for me —
  /// interest cells are inert, "celý den" is hidden, and a hint explains why.
  final String? lockedVenues;

  @override
  ConsumerState<_DayRow> createState() => _DayRowState();
}

class _DayRowState extends ConsumerState<_DayRow> {
  /// Whole-day bulk write in flight — swap the button for a spinner.
  bool _busy = false;

  Day get day => widget.day;
  List<Slot> get slots => widget.slots;
  Heatmap get heatmap => widget.heatmap;
  List<Profile> get members => widget.members;
  String? get uid => widget.uid;
  bool get readOnly => widget.readOnly;

  /// One tap for the whole day: tick everything, or untick everything when
  /// all of the day's slots are already mine.
  Future<void> _selectDay(bool allMine) async {
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      await tryAction(
        context,
        () => Api.setAvailabilityBulk(
            [for (final s in slots) s.id], !allMine),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _locked => widget.lockedVenues != null;

  @override
  Widget build(BuildContext context) {
    final dayStats = heatmap.byDay[day];
    final showWhoIsIn = ref.watch(showWhoIsInProvider);
    final allMine = uid != null &&
        slots.every(
            (s) => heatmap.bySlotId[s.id]?.userIds.contains(uid) ?? false);

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
                Text('${peopleLabel(dayStats.distinctPlayers)} může',
                    style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              // Committed this day -> the day is settled for me, no bulk tick.
              if (!readOnly && !_locked && slots.isNotEmpty)
                _busy
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : TextButton(
                        style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        onPressed: () => _selectDay(allMine),
                        child: Text(allMine ? 'zrušit den' : 'celý den'),
                      ),
            ],
          ),
          const SizedBox(height: 4),
          // I'm playing this day — say where, so my hidden interest makes sense.
          if (_locked)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.event_available,
                      size: 15, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Hraješ tento den v: ${widget.lockedVenues}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary)),
                  ),
                ],
              ),
            ),
          // Ordered starts of the day — a different SHAPE on purpose, so an
          // order can't be confused with an interest cell.
          if (widget.orderedChips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final chip in widget.orderedChips)
                    ActionChip(
                      avatar: const Icon(Icons.check_circle,
                          size: 16, color: Colors.green),
                      label: Text(
                          '${chip.time.display()} · '
                          '${lanesLabel(chip.lanes)} · '
                          '${peopleLabel(chip.players)}'),
                      side: const BorderSide(color: Colors.green),
                      backgroundColor: Color.lerp(
                          Theme.of(context).colorScheme.surface,
                          Colors.green,
                          0.12),
                      onPressed: widget.onOrderedTap,
                    ),
                ],
              ),
            ),
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
    // Interest suppression of committed players is already applied in the
    // heatmap (effectiveAvailabilityProvider), so the count is straight.
    final mine = uid != null && (stats?.userIds.contains(uid) ?? false);

    final cell = SlotCell(
      time: slot.time,
      count: stats?.count ?? 0,
      intensity: heatmap.intensity(slot.id),
      isOrderable: stats?.isOrderable ?? false,
      mine: mine,
      venueFree: slot.venueFree,
      venueOurs: slot.venueOccupiedOurs ?? 0,
      // Through tryAction so a dropped connection is a friendly snackbar, not
      // an uncaught (fatal) error — the tap is otherwise fire-and-forget.
      // Locked = I already play this day -> inert (interest is settled).
      onTap: readOnly || _locked
          ? null
          : () {
              HapticFeedback.lightImpact();
              tryAction(context, () => Api.setAvailability(slot.id, !mine));
            },
      // Scraped slots are owned by the web sync — no manual deletion.
      onLongPress: readOnly || _locked || slot.hasVenueInfo
          ? null
          : () => _confirmDelete(context, slot),
    );
    return _locked ? Opacity(opacity: 0.45, child: cell) : cell;
  }

  /// Who can make this day, one entry per person with a summarized range
  /// ("Pavel: celý den · Miloš: od 17:00") instead of a line per slot.
  /// Shown when the team-wide "who's in" toggle is on.
  Widget _whoIsIn(BuildContext context) {
    final byUser =
        summarizeDayByUser(daySlots: slots, statsBySlotId: heatmap.bySlotId);
    if (byUser.isEmpty) return const SizedBox.shrink();

    final entries = [
      for (final e in byUser.entries)
        (name: memberName(members, e.key), label: e.value),
    ]..sort((a, b) => a.name.compareTo(b.name));

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodySmall,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const TextSpan(text: '  ·  '),
                TextSpan(
                  text: '${entries[i].name}: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: entries[i].label),
              ],
            ],
          ),
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
  const _BestPicksCard({
    required this.tournament,
    required this.heatmap,
    this.orderedLanesBySlot = const {},
  });

  final Tournament tournament;
  final Heatmap heatmap;

  /// slot id -> lanes in active orders; an ordered pick shows the order
  /// instead of the player count.
  final Map<String, int> orderedLanesBySlot;

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
                    '${(orderedLanesBySlot[p.slot.id] ?? 0) > 0 ? 'objednáno ${lanesLabel(orderedLanesBySlot[p.slot.id]!)}' : '${p.count} hráčů'}'),
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
        directlyOrdered: direct,
      ),
    ));
  }
}
