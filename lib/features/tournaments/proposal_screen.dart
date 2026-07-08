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
  /// Selected slots with the number of places to order for each. Usually the
  /// kind's lane capacity, but the team often orders more than the currently
  /// signed-up players — someone joins later even if they never ticked.
  late final Map<String, int> _selected = {
    for (final id in widget.preselected)
      id: widget.tournament.kind.laneCapacity,
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
        placesBySlot: _selected,
        note: _note.text.trim(),
        directlyOrdered: widget.directlyOrdered,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
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

    final capacity = widget.tournament.kind.laneCapacity;
    final totalPlaces = _selected.values.fold(0, (sum, n) => sum + n);
    final placesInfo = '${_selected.length} startů = $totalPlaces míst';

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
              CheckboxListTile(
                dense: true,
                value: _selected.containsKey(slot.id),
                onChanged: (checked) => setState(() {
                  checked == true
                      ? _selected[slot.id] = capacity
                      : _selected.remove(slot.id);
                }),
                title: Row(
                  children: [
                    Expanded(child: Text(slot.time.display())),
                    if (_selected.containsKey(slot.id))
                      _PlacesStepper(
                        places: _selected[slot.id]!,
                        onChanged: (n) =>
                            setState(() => _selected[slot.id] = n),
                      ),
                  ],
                ),
                subtitle: Text(
                    '${heatmap.bySlotId[slot.id]?.count ?? 0} hráčů může'),
              ),
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
            'Počet míst u startu jde zvýšit — klidně objednej víc, '
            'než se zatím hlásí.',
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

/// Compact "− n míst +" control for one selected start.
class _PlacesStepper extends StatelessWidget {
  const _PlacesStepper({required this.places, required this.onChanged});

  final int places;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: places > 1 ? () => onChanged(places - 1) : null,
        ),
        Text('$places míst', style: Theme.of(context).textTheme.bodyMedium),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, size: 20),
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(places + 1),
        ),
      ],
    );
  }
}
