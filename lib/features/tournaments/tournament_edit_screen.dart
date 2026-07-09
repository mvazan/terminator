import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/day_groups.dart';
import '../../domain/models.dart';
import '../../scrape/scraper.dart';
import '../venues/venue_editor.dart';

/// Create or edit a tournament.
///
/// Slots come either from the organizer's reservation page (recognized URL →
/// scraped automatically, incl. occupancy) or from manual patterns: any
/// number of day groups (pick weekdays, type times like "16 17:30 19").
///
/// [duplicateFrom] pre-fills every field (name, venue, kind, contacts, URL)
/// from a past tournament — typically an archived one, "next season" — but
/// the dates are left blank and nothing else (slots, votes, orders, rosters)
/// carries over: this is a brand-new tournament, just saving retyping.
class TournamentEditScreen extends ConsumerStatefulWidget {
  const TournamentEditScreen({super.key, this.existing, this.duplicateFrom});

  final Tournament? existing;
  final Tournament? duplicateFrom;

  @override
  ConsumerState<TournamentEditScreen> createState() =>
      _TournamentEditScreenState();
}

class _GroupDraft {
  _GroupDraft(this.weekdays, [List<HourMinute>? times])
      : times = times ?? [];

  final Set<int> weekdays;
  final List<HourMinute> times;
}

class _TournamentEditScreenState extends ConsumerState<TournamentEditScreen> {
  // Prefill source: editing an existing tournament copies everything
  // including dates; duplicating copies settings only, dates start blank.
  Tournament? get _prefill => widget.existing ?? widget.duplicateFrom;

  late final _name = TextEditingController(text: _prefill?.name);

  /// Selected saved venue — required. Its lane count caps ordered places and
  /// its name is stored in the tournament's venue column.
  late String? _venueId = _prefill?.venueId;
  late final _email = TextEditingController(text: _prefill?.contactEmail);
  late final _phone = TextEditingController(text: _prefill?.contactPhone);
  late final _url = TextEditingController(text: _prefill?.sourceUrl);
  late final _notes = TextEditingController(text: _prefill?.notes);
  late final _minPlayers =
      TextEditingController(text: '${_prefill?.minPlayers ?? 2}');
  late TournamentKind _kind;
  late Discipline? _discipline = _prefill?.discipline;

  Day? _startsOn;
  Day? _endsOn;
  late final List<_GroupDraft> _groups = [
    _GroupDraft({1, 2, 3, 4, 5}),
    _GroupDraft({6, 7}),
  ];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;
  TournamentScraper? get _scraper => ScraperRegistry.forUrl(_url.text);

  @override
  void initState() {
    super.initState();
    _kind = _prefill?.kind ?? TournamentKind.dvojice;
    if (widget.existing != null) {
      _startsOn = widget.existing!.startsOn;
      _endsOn = widget.existing!.endsOn;
    }
    _url.addListener(_onUrlChanged);
  }

  void _onUrlChanged() => setState(() {});

  @override
  void dispose() {
    _url.removeListener(_onUrlChanged);
    for (final controller in [
      _name, _email, _phone, _url, _notes, _minPlayers,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<DayGroup> _filledGroups() => [
        for (final draft in _groups)
          if (draft.weekdays.isNotEmpty && draft.times.isNotEmpty)
            DayGroup(weekdays: draft.weekdays, times: draft.times),
      ];

  int get _previewCount {
    if (_startsOn == null || _endsOn == null) return 0;
    return generateSlotsFromGroups(
      startsOn: _startsOn!,
      endsOn: _endsOn!,
      groups: _filledGroups(),
    ).length;
  }

  Future<void> _pickDateRange() async {
    DateTimeRange? initial;
    if (_startsOn != null && _endsOn != null) {
      initial = DateTimeRange(
        start: DateTime(_startsOn!.year, _startsOn!.month, _startsOn!.day),
        end: DateTime(_endsOn!.year, _endsOn!.month, _endsOn!.day),
      );
    }
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      helpText: 'Termín turnaje od–do',
    );
    if (picked == null) return;
    setState(() {
      _startsOn = Day.fromDateTime(picked.start);
      _endsOn = Day.fromDateTime(picked.end);
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final scraping = _scraper != null;
    final venue = ref.read(venueByIdProvider(_venueId));
    if (name.isEmpty || _startsOn == null || _endsOn == null) {
      snack(context, 'Vyplň aspoň název a termín od–do.');
      return;
    }
    if (venue == null) {
      snack(context, 'Vyber kuželnu.');
      return;
    }

    List<DayGroup> groups = const [];
    if (!_isEdit && !scraping) {
      groups = _filledGroups();
      if (groups.isEmpty) {
        snack(context, 'Přidej aspoň jeden čas startu (nebo web turnaje).');
        return;
      }
    }

    final fields = {
      'name': name,
      'venue_id': _venueId,
      'kind': _kind.label,
      'discipline': _discipline?.label,
      'starts_on': _startsOn!.toSql(),
      'ends_on': _endsOn!.toSql(),
      'min_players': int.tryParse(_minPlayers.text) ?? 2,
      'contact_email': _email.text.trim(),
      'contact_phone': _phone.text.trim(),
      'source_url': _url.text.trim(),
      'notes': _notes.text.trim(),
    };

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        await Api.updateTournament(widget.existing!.id, fields);
      } else {
        final specs = generateSlotsFromGroups(
          startsOn: _startsOn!,
          endsOn: _endsOn!,
          groups: groups,
        );
        final id = await Api.createTournament(
          tournament: {...fields, 'created_by': currentUserId},
          slotRows: [
            for (final s in specs)
              {'date': s.date.toSql(), 'time': s.time.toSql()},
          ],
        );
        if (scraping) {
          final count = await Api.syncFromWeb(
              tournamentId: id, sourceUrl: _url.text.trim());
          if (mounted) snack(context, 'Načteno $count startů z webu.');
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) snack(context, 'Uložení se nepovedlo: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _selectVenue(Venue? venue) {
    setState(() {
      _venueId = venue?.id;
      // Prefill the home-club website; organizer contacts stay on the
      // tournament (a venue may host several clubs).
      if (venue != null && venue.sourceUrl.isNotEmpty) {
        _url.text = venue.sourceUrl;
      }
    });
  }

  /// Pick a saved venue (required — its lane count caps ordered places) or add
  /// a new one inline.
  Widget _venuePicker() {
    final venues = ref.watch(venuesProvider).value ?? const [];
    final selected =
        venues.where((v) => v.id == _venueId).firstOrNull;

    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: selected?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Kuželna'),
            hint: const Text('Vyber kuželnu'),
            items: [
              for (final v in venues)
                DropdownMenuItem(
                  value: v.id,
                  child: Text('${v.name} · ${lanesLabel(v.laneCount)}',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (id) => _selectVenue(
                venues.where((v) => v.id == id).firstOrNull),
          ),
        ),
        IconButton(
          tooltip: 'Nová kuželna',
          icon: const Icon(Icons.add_location_alt_outlined),
          onPressed: () async {
            final id = await editVenue(context);
            if (id != null) {
              final v = ref.read(venueByIdProvider(id));
              if (v != null) _selectVenue(v);
            }
          },
        ),
        if (selected != null)
          IconButton(
            tooltip: 'Upravit kuželnu',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => editVenue(context, existing: selected),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scraping = _scraper != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit
            ? 'Upravit turnaj'
            : (widget.duplicateFrom != null
                ? 'Nová sezóna — ${widget.duplicateFrom!.name}'
                : 'Nový turnaj')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Název turnaje'),
          ),
          const SizedBox(height: 12),
          _venuePicker(),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<TournamentKind>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Typ'),
                items: [
                  for (final kind in TournamentKind.values)
                    DropdownMenuItem(value: kind, child: Text(kind.label)),
                ],
                onChanged: (kind) => setState(() => _kind = kind!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<Discipline?>(
                initialValue: _discipline,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Disciplína'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  for (final d in Discipline.values)
                    DropdownMenuItem(value: d, child: Text(d.label)),
                ],
                onChanged: (d) => setState(() => _discipline = d),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range),
            label: Text(_startsOn == null || _endsOn == null
                ? 'Termín od–do'
                : rangeLabel(_startsOn!, _endsOn!)),
            onPressed: _pickDateRange,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _minPlayers,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Min. hráčů na start',
              helperText:
                  'Od kolika hráčů pošle appka upozornění „dá se objednat"',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration:
                    const InputDecoration(labelText: 'E-mail pořadatele'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration:
                    const InputDecoration(labelText: 'Telefon pořadatele'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Web turnaje (rezervační stránka)',
              helperText: scraping
                  ? '✓ Rozpoznáno (${_scraper!.name}) — termíny a obsazenost '
                      'se načtou z webu automaticky.'
                  : (_url.text.trim().isEmpty
                      ? 'Nepovinné. U kkmoravskaslavia.cz se termíny '
                          'načtou samy.'
                      : 'Neznámý web — termíny zadej ručně níže.'),
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Poznámky'),
          ),
          if (!_isEdit && !scraping) ...[
            const SizedBox(height: 20),
            Text('Časy startů',
                style: Theme.of(context).textTheme.titleMedium),
            Text(
              'Vyber dny a napiš časy — třeba „16 17:30 19". '
              'Skupin můžeš mít kolik chceš.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final (i, group) in _groups.indexed)
              _GroupEditor(
                key: ObjectKey(group),
                group: group,
                onChanged: () => setState(() {}),
                onRemove: _groups.length > 1
                    ? () => setState(() => _groups.removeAt(i))
                    : null,
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Přidat skupinu dnů'),
                onPressed: () =>
                    setState(() => _groups.add(_GroupDraft({}))),
              ),
            ),
            const SizedBox(height: 4),
            Text('Vytvoří se $_previewCount startů.',
                style: Theme.of(context).textTheme.titleSmall),
          ],
          if (_isEdit)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                scraping
                    ? 'Termíny a obsazenost se synchronizují z webu '
                        '(tlačítko v detailu turnaje).'
                    : 'Jednotlivé starty přidáš/odebereš v detailu turnaje '
                        '(dlouhým podržením).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving
                ? 'Ukládám…'
                : (_isEdit ? 'Uložit změny' : 'Založit turnaj')),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _GroupEditor extends StatelessWidget {
  const _GroupEditor({
    super.key,
    required this.group,
    required this.onChanged,
    this.onRemove,
  });

  final _GroupDraft group;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  Future<void> _addTime(BuildContext context) async {
    // Opens the native time picker repeatedly — pick a time, it's added as a
    // chip, the picker reopens automatically so you can keep adding times
    // for this day group until you tap Cancel.
    while (true) {
      final picked = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 17, minute: 0),
        helpText: 'PŘIDAT ČAS STARTU',
        confirmText: 'Přidat',
        cancelText: 'Hotovo',
      );
      if (picked == null || !context.mounted) return;
      final time = HourMinute(picked.hour, picked.minute);
      if (!group.times.contains(time)) {
        group.times.add(time);
        group.times.sort();
      }
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (var day = 1; day <= 7; day++)
                        FilterChip(
                          label: Text(weekdaysShort[day - 1]),
                          visualDensity: VisualDensity.compact,
                          selected: group.weekdays.contains(day),
                          onSelected: (selected) {
                            selected
                                ? group.weekdays.add(day)
                                : group.weekdays.remove(day);
                            onChanged();
                          },
                        ),
                    ],
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: 'Odebrat skupinu',
                    onPressed: onRemove,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Časy startů', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final time in group.times)
                  InputChip(
                    label: Text(time.display()),
                    onDeleted: () {
                      group.times.remove(time);
                      onChanged();
                    },
                  ),
                ActionChip(
                  avatar: const Icon(Icons.access_time, size: 18),
                  label: const Text('přidat čas'),
                  onPressed: () => _addTime(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
