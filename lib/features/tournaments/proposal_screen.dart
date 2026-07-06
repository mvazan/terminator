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
  late final Set<String> _selected = {...widget.preselected};
  final _note = TextEditingController();
  bool _saving = false;

  Future<void> _submit() async {
    if (_selected.isEmpty) {
      snack(context, 'Vyber aspoň jeden start.');
      return;
    }
    setState(() => _saving = true);
    try {
      await Api.createProposal(
        tournamentId: widget.tournament.id,
        slotIds: _selected,
        note: _note.text.trim(),
        directlyOrdered: widget.directlyOrdered,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) snack(context, 'Nepovedlo se: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = (ref.watch(slotsProvider).value ?? const [])
        .where((s) => s.tournamentId == widget.tournament.id)
        .toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        return a.time.compareTo(b.time);
      });
    final slotIds = {for (final s in slots) s.id};
    final availability = (ref.watch(availabilityProvider).value ?? const [])
        .where((a) => slotIds.contains(a.slotId))
        .toList();
    final heatmap = Heatmap.build(
      tournament: widget.tournament,
      slots: slots,
      availability: availability,
    );

    final byDay = <Day, List<Slot>>{};
    for (final s in slots) {
      byDay.putIfAbsent(s.date, () => []).add(s);
    }

    final capacity = widget.tournament.maxPlayers;
    final placesInfo = capacity == null
        ? '${_selected.length} startů'
        : '${_selected.length} startů = ${_selected.length * capacity} míst';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.directlyOrdered
            ? 'Zaznamenat objednávku'
            : 'Navrhnout objednávku'),
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
                value: _selected.contains(slot.id),
                onChanged: (checked) => setState(() {
                  checked == true
                      ? _selected.add(slot.id)
                      : _selected.remove(slot.id);
                }),
                title: Text(slot.time.display()),
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
