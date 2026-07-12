import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/geocoding.dart';
import '../../domain/models.dart';

/// Lane counts offered in the picker (bowling alleys come in even sizes).
const _laneOptions = [2, 4, 6, 8];

/// Add or edit a bowling alley. Only the lane count is required. Returns the
/// venue id (new or edited) on save, or null if cancelled.
Future<String?> editVenue(BuildContext context, {Venue? existing}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _VenueForm(existing: existing),
    ),
  );
}

class _VenueForm extends ConsumerStatefulWidget {
  const _VenueForm({this.existing});

  final Venue? existing;

  @override
  ConsumerState<_VenueForm> createState() => _VenueFormState();
}

class _VenueFormState extends ConsumerState<_VenueForm> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late int _lanes = widget.existing?.laneCount ?? _laneOptions.first;
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _url = TextEditingController(text: widget.existing?.sourceUrl);
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _url]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      snack(context, 'Vyplň název kuželny.');
      return;
    }
    setState(() => _saving = true);
    final address = _address.text.trim();
    final addressChanged =
        widget.existing != null && widget.existing!.address != address;
    final fields = {
      'name': name,
      'lane_count': _lanes,
      'address': address,
      'source_url': _url.text.trim(),
      // A changed address invalidates the old pin — clear coords now so the
      // map never points at the previous place; the geocode below refills.
      if (addressChanged) 'lat': null,
      if (addressChanged) 'lng': null,
    };
    final existing = widget.existing;
    String? id = existing?.id;
    final ok = await tryAction(context, () async {
      if (existing == null) {
        id = await Api.createVenue(fields);
      } else {
        await Api.updateVenue(existing.id, fields);
      }
    });
    if (ok && id != null) {
      // Geocode for the map — new venue, changed address, or missing coords.
      // Fire-and-forget: a save never fails because Nominatim is down.
      final needsCoords =
          existing == null || addressChanged || !existing.hasCoords;
      if (address.isNotEmpty && needsCoords) {
        final venueId = id!;
        unawaited(geocodeAddress(address).then((coords) async {
          if (coords == null) return;
          await Api.updateVenue(
              venueId, {'lat': coords.lat, 'lng': coords.lng});
        }).catchError((_) {}));
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(widget.existing == null ? 'Nová kuželna' : 'Upravit kuželnu',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Název',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue:
              _laneOptions.contains(_lanes) ? _lanes : _laneOptions.first,
          decoration: const InputDecoration(
            labelText: 'Počet drah',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final n in _laneOptions)
              DropdownMenuItem(value: n, child: Text(lanesLabel(n))),
          ],
          onChanged: (n) => setState(() => _lanes = n ?? _lanes),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _address,
          decoration: const InputDecoration(
            labelText: 'Adresa (nepovinné)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Web domácího oddílu (nepovinné)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Ukládám…' : 'Uložit'),
        ),
      ],
    );
  }
}
