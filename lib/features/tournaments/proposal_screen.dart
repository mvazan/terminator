import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/heatmap.dart';
import '../../domain/models.dart';

/// Pick the slots for a proposal ("Beru čtvrtek — kdo je pro?") or record a
/// direct order. Best-pick slots arrive pre-selected.
class ProposalScreen extends ConsumerStatefulWidget {
  const ProposalScreen({
    super.key,
    required this.tournament,
    required this.preselected,
    this.directlyOrdered = false,
  });

  final Tournament tournament;
  final Set<String> preselected;
  final bool directlyOrdered;

  @override
  ConsumerState<ProposalScreen> createState() => _ProposalScreenState();
}

class _ProposalScreenState extends ConsumerState<ProposalScreen> {
  /// Selected slots with the number of *lanes* to order for each. Starts at
  /// one lane; the team can bump it up to the venue's lane count.
  late final Map<String, int> _selected = {
    for (final id in widget.preselected) id: 1,
  };
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected.isEmpty) {
      snack(context, 'Vyber aspoň jeden start.');
      return;
    }
    setState(() => _saving = true);
    final ok = await tryAction(
      context,
      () => Api.createProposal(
        tournamentId: widget.tournament.id,
        lanesBySlot: _selected,
        note: _note.text.trim(),
        directlyOrdered: widget.directlyOrdered,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  /// Most lanes that can be ordered for one start, or null = no limit.
  /// The venue's TOTAL lanes for that start, not just the free ones — the
  /// occupancy may be our own booking made on the venue's site, and ordering
  /// happens outside the app anyway, so occupancy is advisory, never a block.
  int? _maxLanes(Slot slot, Venue? venue) {
    if (slot.hasVenueInfo) return slot.venueCapacity;
    if (venue != null) return venue.laneCount;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final venue = ref.watch(venueByIdProvider(widget.tournament.venueId));
    final slots = (ref.watch(slotsProvider).value ?? const [])
        .where((s) => s.tournamentId == widget.tournament.id)
        .toList()
      ..sort(Slot.compare);
    final slotIds = {for (final s in slots) s.id};
    final availability = (ref.watch(availabilityProvider).value ?? const [])
        .where((a) => slotIds.contains(a.slotId))
        .toList();
    final heatmap = Heatmap.build(
      tournament: widget.tournament,
      slots: slots,
      availability: availability,
    );

    final byDay = slotsByDay(slots);

    final totalLanes = _selected.values.fold(0, (sum, n) => sum + n);
    final placesInfo = '${_selected.length} startů = ${lanesLabel(totalLanes)}';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.directlyOrdered
            ? 'Zaznamenat objednávku'
            : 'Hlasování'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            widget.directlyOrdered
                ? 'Které starty jsi objednal(a)?'
                : 'Které starty navrhuješ vzít? Parta dostane upozornění '
                    'a odhlasuje si to.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          for (final day in byDay.keys) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(dayFull(day),
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final slot in byDay[day]!)
              Builder(builder: (context) {
                final selected = _selected.containsKey(slot.id);
                final max = _maxLanes(slot, venue);
                void toggle() => setState(() {
                      selected
                          ? _selected.remove(slot.id)
                          : _selected[slot.id] = 1;
                    });
                final scheme = Theme.of(context).colorScheme;
                return Column(
                  children: [
                    Container(
                      // Our own venue booking — highlight the start we already
                      // reserved on the venue's site, so it's obvious which
                      // one to record as ordered.
                      color: slot.venueOurs
                          ? scheme.primaryContainer.withValues(alpha: 0.35)
                          : null,
                      child: Row(
                        children: [
                          // Tap target is the checkbox only, not the whole row —
                          // so tapping a disabled stepper button can't toggle it.
                          Checkbox(
                            value: selected,
                            onChanged: (_) => toggle(),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(slot.time.display()),
                                    if (slot.venueOurs) ...[
                                      const SizedBox(width: 6),
                                      Icon(Icons.home,
                                          size: 16, color: scheme.primary),
                                    ],
                                  ],
                                ),
                                Text(
                                  '${heatmap.bySlotId[slot.id]?.count ?? 0} '
                                  'hráčů může'
                                  '${slot.venueOurs ? ' · naše rezervace (${lanesLabel(slot.venueOccupiedOurs!)})' : ''}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            _LanesStepper(
                              lanes: _selected[slot.id]!,
                              max: max,
                              onChanged: (n) =>
                                  setState(() => _selected[slot.id] = n),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                );
              }),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Poznámka (nepovinná)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(placesInfo, style: Theme.of(context).textTheme.titleSmall),
          Text(
            venue == null
                ? 'U startu vyber počet drah, které objednáváš.'
                : 'Počet drah u startu jde zvýšit až po počet drah kuželny '
                    '(${venue.name}: ${venue.laneCount}). U turnajů s webem '
                    'jen po počet volných drah.'
                    '${widget.tournament.kind == TournamentKind.tandem ? '\nV tandemu hrají na jedné dráze 2 hráči.' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: Text(_saving
                ? 'Ukládám…'
                : (widget.directlyOrdered
                    ? 'Zaznamenat jako objednané'
                    : 'Poslat návrh partě')),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Compact "− n drah +" control for one selected start. [max] caps the count
/// (venue lanes, or free lanes when scraped); null = no limit.
class _LanesStepper extends StatelessWidget {
  const _LanesStepper({
    required this.lanes,
    required this.onChanged,
    this.max,
  });

  final int lanes;
  final int? max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final canAdd = max == null || lanes < max!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: lanes > 1 ? () => onChanged(lanes - 1) : null,
        ),
        Text(lanesLabel(lanes), style: Theme.of(context).textTheme.bodyMedium),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: canAdd ? () => onChanged(lanes + 1) : null,
        ),
      ],
    );
  }
}
