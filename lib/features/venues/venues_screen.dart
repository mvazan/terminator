import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'venue_editor.dart';

/// Manage the team's saved bowling alleys. Reached from Tým → Nastavení.
class VenuesScreen extends ConsumerWidget {
  const VenuesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final venues = ref.watch(venuesProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Kuželny')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editVenue(context),
        icon: const Icon(Icons.add),
        label: const Text('Nová kuželna'),
      ),
      body: venues.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Zatím žádná kuželna.\n'
                  'Přidej první — pak ji jde vybrat u turnaje.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                for (final v in venues)
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(v.name),
                    subtitle: Text([
                      '${v.laneCount} drah',
                      if (v.address.isNotEmpty) v.address,
                    ].join(' · ')),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => editVenue(context, existing: v),
                  ),
              ],
            ),
    );
  }
}
