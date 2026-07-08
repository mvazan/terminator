import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';

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
  late final _lanes = TextEditingController(
      text: widget.existing?.laneCount.toString() ?? '');
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _email =
      TextEditingController(text: widget.existing?.contactEmail);
  late final _phone =
      TextEditingController(text: widget.existing?.contactPhone);
  late final _url = TextEditingController(text: widget.existing?.sourceUrl);
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _lanes, _address, _email, _phone, _url]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final lanes = int.tryParse(_lanes.text.trim());
    if (name.isEmpty || lanes == null || lanes < 1) {
      snack(context, 'Vyplň název a počet drah (aspoň 1).');
      return;
    }
    setState(() => _saving = true);
    final fields = {
      'name': name,
      'lane_count': lanes,
      'address': _address.text.trim(),
      'contact_email': _email.text.trim(),
      'contact_phone': _phone.text.trim(),
      'source_url': _url.text.trim(),
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
        TextField(
          controller: _lanes,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Počet drah',
            helperText: 'Povinné — kolik drah kuželna má.',
            border: OutlineInputBorder(),
          ),
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
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'E-mail pořadatele (nepovinné)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Telefon pořadatele (nepovinné)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Web / rezervační stránka (nepovinné)',
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
