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
  /// Scraped slot → free lanes at the venue; otherwise the saved venue's
  /// lane count. (Player capacity per lane, i.e. tandem doubling, only shows
  /// up later when assigning people.)
  int? _maxLanes(Slot slot, Venue? venue) {
    if (slot.hasVenueInfo) return slot.venueFree!.clamp(0, 1 << 30);
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
    final placesInfo = '${_selected.length} startů = $totalLanes drah';

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
                final max = _maxLanes(slot, venue);
                return CheckboxListTile(
                dense: true,
                value: _selected.containsKey(slot.id),
                onChanged: (checked) => setState(() {
                  if (checked == true) {
                    _selected[slot.id] = 1;
                  } else {
                    _selected.remove(slot.id);
                  }
                }),
                title: Row(
                  children: [
                    Expanded(child: Text(slot.time.display())),
                    if (_selected.containsKey(slot.id))
                      _LanesStepper(
                        lanes: _selected[slot.id]!,
                        max: max,
                        onChanged: (n) =>
                            setState(() => _selected[slot.id] = n),
                      ),
                  ],
                ),
                subtitle: Text(
                    '${heatmap.bySlotId[slot.id]?.count ?? 0} hráčů může'),
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
        Text('$lanes drah', style: Theme.of(context).textTheme.bodyMedium),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: canAdd ? () => onChanged(lanes + 1) : null,
        ),
      ],
    );
  }
}
