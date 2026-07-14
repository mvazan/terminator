import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/heatmap.dart';
import '../../domain/models.dart';
import '../../scrape/scraper.dart';
import '../manage/manage_mode.dart';
import 'map_screen.dart';
import 'timeline_screen.dart';
import 'tournament_detail_screen.dart';
import 'tournament_edit_screen.dart';

/// Splits [list] into visible-then-hidden while preserving the incoming order
/// within each group (List.sort is not stable, a partition is).
List<Tournament> _hiddenLast(
        List<Tournament> list, bool Function(Tournament) isHidden) =>
    [...list.where((t) => !isHidden(t)), ...list.where(isHidden)];

class TournamentsScreen extends ConsumerStatefulWidget {
  const TournamentsScreen({super.key});

  @override
  ConsumerState<TournamentsScreen> createState() => _TournamentsScreenState();
}

class _TournamentsScreenState extends ConsumerState<TournamentsScreen>
    with WidgetsBindingObserver {
  /// Eye mode: show also the tournaments I hid, each with a checkbox to
  /// hide/unhide in bulk. Off = hidden ones simply disappear.
  bool _showHidden = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The screen lives in an IndexedStack and is never disposed by
    // navigation; if the OS kills the backgrounded process, dispose() never
    // runs either. Committing on pause is the only reliable way pending
    // eye-mode edits survive leaving the app.
    if (state == AppLifecycleState.paused) _commitSilently();
  }

  /// tournamentId -> desired hidden-for-me. Pending while eye mode is on
  /// (taps are local-only; ONE batched request goes out when it closes),
  /// optimistic overlay afterwards; entries are pruned once the live stream
  /// agrees, so the UI never flickers back.
  final Map<String, bool> _hideOverrides = {};

  /// Snapshot of the live hidden set from the last build — dispose() has no
  /// ref and still needs a diff to commit against.
  Set<String> _lastMyHiddenIds = const {};

  bool _effectiveHidden(String id, Set<String> live) =>
      _hideOverrides[id] ?? live.contains(id);

  /// The batch that would be sent right now: overrides that differ from the
  /// live stream state.
  ({Set<String> hide, Set<String> unhide}) _pendingDiff(Set<String> live) {
    final hide = <String>{};
    final unhide = <String>{};
    _hideOverrides.forEach((id, hidden) {
      if (hidden && !live.contains(id)) hide.add(id);
      if (!hidden && live.contains(id)) unhide.add(id);
    });
    return (hide: hide, unhide: unhide);
  }

  /// How many of MY ticks would be lost by hiding [tournamentIds].
  int _myTicksIn(Set<String> tournamentIds) {
    final uid = currentUserId;
    if (uid == null || tournamentIds.isEmpty) return 0;
    final slotIds = {
      for (final s in ref.read(slotsProvider).value ?? const <Slot>[])
        if (tournamentIds.contains(s.tournamentId)) s.id,
    };
    return (ref.read(availabilityProvider).value ?? const [])
        .where((a) => a.userId == uid && slotIds.contains(a.slotId))
        .length;
  }

  /// Closes eye mode: warns when hides would drop my ticks, then commits the
  /// whole diff as one batch. Cancelling the warning keeps eye mode open with
  /// the pending changes intact.
  Future<void> _closeEyeMode() async {
    final diff = _pendingDiff(_lastMyHiddenIds);
    final lostTicks = _myTicksIn(diff.hide);
    if (lostTicks > 0 && mounted) {
      final confirmed = await confirmDialog(
        context,
        title: 'Skrýt turnaje?',
        message: 'Skrývané turnaje obsahují tvoje zaškrtnuté termíny '
            '($lostTicks) — zruší se.',
        confirmLabel: 'Skrýt',
      );
      if (!confirmed) return; // stay in eye mode, keep pending edits
      // The screen can be swapped out while the dialog is up (sign-out,
      // auth flip) — dispose has already committed then, nothing to do.
      if (!mounted) return;
    }
    setState(() => _showHidden = false);
    if (diff.hide.isEmpty && diff.unhide.isEmpty) return;
    await tryAction(
      context,
      () => Api.setTournamentHidesBatch(hide: diff.hide, unhide: diff.unhide),
    ).then((ok) {
      // On failure drop the overlay so the UI reverts to server truth.
      if (!ok && mounted) setState(_hideOverrides.clear);
    });
  }

  /// Fire-and-forget commit of pending edits — used where no dialogs are
  /// possible (app pause, dispose). Errors just leave server state.
  void _commitSilently() {
    final diff = _pendingDiff(_lastMyHiddenIds);
    if (diff.hide.isEmpty && diff.unhide.isEmpty) return;
    try {
      Api.setTournamentHidesBatch(hide: diff.hide, unhide: diff.unhide)
          .catchError((_) {});
    } catch (_) {
      // Supabase unavailable (tests, teardown) — nothing to do.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _commitSilently();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tournaments = ref.watch(tournamentsProvider);
    final venueNames = ref.watch(venueNamesProvider);
    final interest = ref.watch(tournamentInterestProvider);
    final ordered = ref.watch(orderedSlotsCountProvider);
    final online = ref.watch(realtimeConnectedProvider).value ?? true;
    final now = today();
    final manage = ref.watch(manageUnlockedProvider);
    final hidden = manage
        ? (ref.watch(allTournamentsProvider).value ?? const [])
            .where((t) => t.isHidden)
            .toList()
        : const <Tournament>[];
    // Tournaments the current user hid for themselves ("not interested").
    final myHiddenIds =
        ref.watch(myHiddenTournamentsProvider).value ?? const <String>{};
    _lastMyHiddenIds = myHiddenIds;
    // Prune overrides the stream has caught up with.
    _hideOverrides
        .removeWhere((id, hidden) => myHiddenIds.contains(id) == hidden);

    return Scaffold(
      appBar: AppBar(
        // Long-press the title to reach the hidden manage mode (PIN-gated).
        title: ManageGestureTitle(
          child: const Text('Turnaje'),
        ),
        actions: [
          // Eye mode: reveal my hidden tournaments with checkboxes to
          // hide/unhide in bulk; closing commits everything at once.
          IconButton(
            tooltip: !online
                ? 'Offline — skrývání je jen ke čtení'
                : (_showHidden
                    ? 'Hotovo — skrýt odškrtnuté'
                    : 'Zobrazit skryté turnaje'),
            icon: Icon(_showHidden
                ? Icons.visibility
                : Icons.visibility_off_outlined),
            // Offline the batch couldn't be saved — don't let edits start.
            onPressed: !online && !_showHidden
                ? null
                : () {
                    if (_showHidden) {
                      _closeEyeMode();
                    } else {
                      setState(() => _showHidden = true);
                    }
                  },
          ),
          IconButton(
            tooltip: 'Mapa kuželen',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MapScreen()),
            ),
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
        data: (_) {
          // Both modes filter from the full team-visible list so the local
          // overrides can win over the (possibly lagging) live stream.
          final teamVisible = [
            for (final t in (ref.watch(allTournamentsProvider).value ??
                const <Tournament>[]))
              if (!t.isHidden) t,
          ];
          final all = _showHidden
              ? teamVisible
              : [
                  for (final t in teamVisible)
                    if (!_effectiveHidden(t.id, myHiddenIds)) t,
                ];
          var active = [
            for (final t in all)
              if (!t.isArchived && !t.endsOn.isBefore(now)) t,
          ];
          var past = [
            for (final t in all)
              if (t.isArchived || t.endsOn.isBefore(now)) t,
          ]..sort((a, b) => b.endsOn.compareTo(a.endsOn));
          if (_showHidden) {
            // Sort by the SAVED state only — rows must not jump around while
            // the user is still ticking; they move on the next eye-open,
            // after the batch is committed.
            bool isHidden(Tournament t) => myHiddenIds.contains(t.id);
            active = _hiddenLast(active, isHidden);
            past = _hiddenLast(past, isHidden);
          }

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
                interest: interest[t.id],
                orderedCount: ordered[t.id] ?? 0,
                hiddenByMe:
                    _showHidden ? _effectiveHidden(t.id, myHiddenIds) : null,
                onHiddenByMeChanged: _showHidden
                    ? (hidden) =>
                        setState(() => _hideOverrides[t.id] = hidden)
                    : null,
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
                        subtitle: Text(
                            t.timelineLabel(venueNames[t.venueId] ?? '?')),
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

/// The compact interest line: people, strongest day (only when it differs),
/// and ordered slots — e.g. "7 lidí · nej. den 5 · 3 obj." Null when there's
/// nothing to say (nobody ticked and nothing ordered).
String? _interestLine(TournamentInterest? i, int ordered) {
  final parts = <String>[];
  if (i != null && i.players > 0) {
    if (i.players == 1) {
      parts.add(peopleLabel(1)); // "1 člověk"
    } else {
      parts.add(peopleLabel(i.players)); // "7 lidí"
      // Strongest day only adds info when people are spread across days.
      if (i.bestDayPlayers < i.players) parts.add('nej. den ${i.bestDayPlayers}');
    }
  }
  if (ordered > 0) parts.add('$ordered obj.');
  return parts.isEmpty ? null : parts.join(' · ');
}

class _TournamentTile extends StatelessWidget {
  const _TournamentTile({
    required this.tournament,
    required this.now,
    required this.venueName,
    this.interest,
    this.orderedCount = 0,
    this.hiddenByMe,
    this.onHiddenByMeChanged,
  });

  final Tournament tournament;
  final Day now;
  final String venueName;

  /// Availability interest for the second subtitle line; null = nobody ticked.
  final TournamentInterest? interest;

  /// How many slots here are already ordered — the "3 obj." on that line.
  final int orderedCount;

  /// Non-null = eye mode: show a checkbox (checked = visible for me) and dim
  /// the tile when hidden. Null = normal browsing, no checkbox.
  final bool? hiddenByMe;
  final ValueChanged<bool>? onHiddenByMeChanged;

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

    final mine = interest?.mine ?? false;
    final interestLine = _interestLine(interest, orderedCount);

    // Kind · discipline. The dates live in the left rail (start on top,
    // end at the bottom), so the meta line doesn't repeat them.
    final meta = [
      t.kind.label,
      if (t.discipline != null) t.discipline!.label,
    ].join(' · ');

    final textTheme = Theme.of(context).textTheme;
    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: Container(
        // "I ticked something here" = primary accent strip on the left.
        decoration: mine
            ? BoxDecoration(
                border: Border(
                    left: BorderSide(color: scheme.primary, width: 3)))
            : null,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TournamentDetailScreen(tournamentId: t.id),
            ),
          ),
          // Left rail = the od–do dates spanning the card height; right of
          // the divider a single hierarchy: venue (+globe/chip), name,
          // kind·discipline, interest.
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DateRail(start: t.startsOn, end: t.endsOn),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: VerticalDivider(
                        width: 1, color: scheme.outlineVariant),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Venue — the team thinks in alleys.
                            Expanded(
                              child: Text(venueName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.titleLarge?.copyWith(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700)),
                            ),
                            // Eye mode swaps the status cluster for a
                            // checkbox: checked = visible for me. Taps stay
                            // local; the batch goes out on eye-close.
                            if (hiddenByMe != null)
                              Checkbox(
                                value: !hiddenByMe!,
                                visualDensity: VisualDensity.compact,
                                onChanged: (v) =>
                                    onHiddenByMeChanged?.call(v != true),
                              )
                            else ...[
                              // Manual tournaments (no recognized web) get a
                              // crossed-out globe; the synced majority stays
                              // unmarked.
                              if (ScraperRegistry.forUrl(t.sourceUrl) ==
                                  null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      right: 8, top: 2),
                                  child: Tooltip(
                                    message: 'Bez webu — termíny se '
                                        'zadávají ručně',
                                    child: Icon(Icons.public_off,
                                        size: 16, color: scheme.outline),
                                  ),
                                ),
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
                          ],
                        ),
                        Text(t.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text(meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        if (interestLine != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.groups,
                                  size: 14,
                                  color: mine
                                      ? scheme.primary
                                      : scheme.outline),
                              const SizedBox(width: 4),
                              Text(interestLine,
                                  style: textTheme.bodySmall),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // Hidden ones are dimmed while revealed in eye mode.
    return hiddenByMe == true ? Opacity(opacity: 0.5, child: card) : card;
  }
}

/// The od–do rail on the card's left: start date on top, end date at the
/// bottom (omitted for single-day tournaments), each as "31.7." over the
/// short weekday.
class _DateRail extends StatelessWidget {
  const _DateRail({required this.start, required this.end});

  final Day start;
  final Day end;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget block(Day d, {required bool muted}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${d.day}.${d.month}.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
                color: muted ? scheme.outline : scheme.onSurface,
              ),
            ),
            Text(
              weekdaysShort[d.weekday - 1],
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ],
        );

    return SizedBox(
      width: 48,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          block(start, muted: false),
          if (end != start) block(end, muted: true),
        ],
      ),
    );
  }
}
