import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import '../../domain/slot_generator.dart';

/// Create (or edit the metadata of) a tournament. On create, the start grid
/// is generated from the weekday/weekend time patterns; individual slots can
/// be added/removed later in the detail screen.
class TournamentEditScreen extends StatefulWidget {
  const TournamentEditScreen({super.key, this.existing});

  final Tournament? existing;

  @override
  State<TournamentEditScreen> createState() => _TournamentEditScreenState();
}

class _TournamentEditScreenState extends State<TournamentEditScreen> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _venue = TextEditingController(text: widget.existing?.venue);
  late final _kind = TextEditingController(text: widget.existing?.kind);
  late final _contact =
      TextEditingController(text: widget.existing?.orderingContact);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late final _minPlayers =
      TextEditingController(text: '${widget.existing?.minPlayers ?? 2}');
  late final _maxPlayers = TextEditingController(
      text: widget.existing?.maxPlayers?.toString() ?? '2');

  Day? _startsOn;
  Day? _endsOn;
  final List<HourMinute> _weekdayTimes = [];
  final List<HourMinute> _weekendTimes = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _startsOn = widget.existing?.startsOn;
    _endsOn = widget.existing?.endsOn;
  }

  int get _previewCount => (_startsOn == null || _endsOn == null)
      ? 0
      : generateSlots(
          startsOn: _startsOn!,
          endsOn: _endsOn!,
          weekdayTimes: _weekdayTimes,
          weekendTimes: _weekendTimes,
        ).length;

  Future<void> _pickDate({required bool start}) async {
    final initial = (start ? _startsOn : _endsOn) ?? today();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    setState(() {
      final day = Day.fromDateTime(picked);
      if (start) {
        _startsOn = day;
        if (_endsOn == null || _endsOn!.isBefore(day)) _endsOn = day;
      } else {
        _endsOn = day;
      }
    });
  }

  Future<void> _addTime(List<HourMinute> list) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 0),
    );
    if (picked == null) return;
    setState(() {
      final t = HourMinute(picked.hour, picked.minute);
      if (!list.contains(t)) list.add(t);
      list.sort();
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _startsOn == null || _endsOn == null) {
      snack(context, 'Vyplň aspoň název a termín od–do.');
      return;
    }
    final minPlayers = int.tryParse(_minPlayers.text) ?? 2;
    final maxPlayers = int.tryParse(_maxPlayers.text);
    if (!_isEdit && _weekdayTimes.isEmpty && _weekendTimes.isEmpty) {
      snack(context, 'Přidej aspoň jeden čas startu.');
      return;
    }

    final fields = {
      'name': name,
      'venue': _venue.text.trim(),
      'kind': _kind.text.trim(),
      'starts_on': _startsOn!.toSql(),
      'ends_on': _endsOn!.toSql(),
      'min_players': minPlayers,
      'max_players': maxPlayers,
      'ordering_contact': _contact.text.trim(),
      'notes': _notes.text.trim(),
    };

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await Api.updateTournament(widget.existing!.id, fields);
      } else {
        final specs = generateSlots(
          startsOn: _startsOn!,
          endsOn: _endsOn!,
          weekdayTimes: _weekdayTimes,
          weekendTimes: _weekendTimes,
        );
        await Api.createTournament(
          tournament: {...fields, 'created_by': currentUserId},
          slotRows: [
            for (final s in specs)
              {'date': s.date.toSql(), 'time': s.time.toSql()},
          ],
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) snack(context, 'Uložení se nepovedlo: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Upravit turnaj' : 'Nový turnaj'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Název turnaje', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _venue,
                decoration: const InputDecoration(
                    labelText: 'Kuželna', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _kind,
                decoration: const InputDecoration(
                    labelText: 'Typ (dvojice…)', border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.today),
                label: Text(_startsOn == null
                    ? 'Začátek'
                    : dayLabel(_startsOn!)),
                onPressed: () => _pickDate(start: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(_endsOn == null ? 'Konec' : dayLabel(_endsOn!)),
                onPressed: () => _pickDate(start: false),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _minPlayers,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Min. hráčů na start',
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _maxPlayers,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Hráčů na start (kapacita)',
                    border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _contact,
            decoration: const InputDecoration(
                labelText: 'Kontakt na pořadatele (e-mail / telefon / web)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Poznámky', border: OutlineInputBorder()),
          ),
          if (!_isEdit) ...[
            const SizedBox(height: 20),
            _TimesEditor(
              title: 'Časy startů — všední dny (po–pá)',
              times: _weekdayTimes,
              onAdd: () => _addTime(_weekdayTimes),
              onRemove: (t) => setState(() => _weekdayTimes.remove(t)),
            ),
            const SizedBox(height: 12),
            _TimesEditor(
              title: 'Časy startů — víkend (so–ne)',
              times: _weekendTimes,
              onAdd: () => _addTime(_weekendTimes),
              onRemove: (t) => setState(() => _weekendTimes.remove(t)),
            ),
            const SizedBox(height: 12),
            Text('Vytvoří se $_previewCount startů.',
                style: Theme.of(context).textTheme.bodyMedium),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('Jednotlivé starty přidáš/odebereš v detailu '
                  'turnaje (dlouhým podržením).'),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving
                ? 'Ukládám…'
                : (_isEdit ? 'Uložit změny' : 'Založit turnaj')),
          ),
        ],
      ),
    );
  }
}

class _TimesEditor extends StatelessWidget {
  const _TimesEditor({
    required this.title,
    required this.times,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final List<HourMinute> times;
  final VoidCallback onAdd;
  final ValueChanged<HourMinute> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final t in times)
              InputChip(
                label: Text(t.display()),
                onDeleted: () => onRemove(t),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('přidat čas'),
              onPressed: onAdd,
            ),
          ],
        ),
      ],
    );
  }
}
