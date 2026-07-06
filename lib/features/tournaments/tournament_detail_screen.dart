import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/heatmap.dart';
import '../../domain/models.dart';
import '../chats/chat_screen.dart';
import 'order_card.dart';
import 'proposal_screen.dart';
import 'slot_cell.dart';
import 'tournament_edit_screen.dart';

class TournamentDetailScreen extends ConsumerWidget {
  const TournamentDetailScreen({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tournaments = ref.watch(tournamentsProvider).value ?? const [];
    final tournament =
        tournaments.where((t) => t.id == tournamentId).firstOrNull;
    if (tournament == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final slots = (ref.watch(slotsProvider).value ?? const [])
        .where((s) => s.tournamentId == tournamentId)
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
      tournament: tournament,
      slots: slots,
      availability: availability,
    );
    final orders = (ref.watch(ordersProvider).value ?? const [])
        .where((o) => o.tournamentId == tournamentId)
        .toList();
    final uid = currentUserId;

    final slotsByDay = <Day, List<Slot>>{};
    for (final s in slots) {
      slotsByDay.putIfAbsent(s.date, () => []).add(s);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tournament.name),
        actions: [
          IconButton(
            tooltip: 'Chat k turnaji',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(tournamentId: tournamentId),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (action) => _menuAction(context, action, tournament),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Upravit turnaj')),
              PopupMenuItem(value: 'add_slot', child: Text('Přidat start')),
              PopupMenuItem(value: 'archive', child: Text('Archivovat')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _InfoCard(tournament: tournament),
          const SizedBox(height: 12),
          Text('Kdy můžeš? Odklikni si starty:',
              style: Theme.of(context).textTheme.titleMedium),
          Text(
            'Číslo = kolik nás může. Rámeček = dá se objednat '
            '(min. ${tournament.minPlayers}).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (final day in slotsByDay.keys)
            _DayRow(
              day: day,
              slots: slotsByDay[day]!,
              heatmap: heatmap,
              uid: uid,
            ),
          const SizedBox(height: 16),
          _BestPicksCard(tournament: tournament, heatmap: heatmap),
          const SizedBox(height: 16),
          if (orders.any((o) => o.status != OrderStatus.cancelled)) ...[
            Text('Návrhy a objednávky',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final order in orders)
              if (order.status != OrderStatus.cancelled)
                OrderCard(order: order, tournament: tournament),
          ],
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Future<void> _menuAction(
      BuildContext context, String action, Tournament tournament) async {
    switch (action) {
      case 'edit':
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TournamentEditScreen(existing: tournament)));
      case 'add_slot':
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 30)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (date == null || !context.mounted) return;
        final time = await showTimePicker(
            context: context,
            initialTime: const TimeOfDay(hour: 17, minute: 0));
        if (time == null || !context.mounted) return;
        await tryAction(
          context,
          () => Api.addSlot(tournament.id, Day.fromDateTime(date),
              HourMinute(time.hour, time.minute)),
          success: 'Start přidán.',
        );
      case 'archive':
        await tryAction(context, () => Api.archiveTournament(tournament.id),
            success: 'Turnaj archivován.');
        if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${t.timelineLabel} · ${rangeLabel(t.startsOn, t.endsOn)}'),
            Text('Na start: min. ${t.minPlayers}'
                '${t.maxPlayers != null ? ', hraje ${t.maxPlayers}' : ''}'),
            if (t.orderingContact.isNotEmpty)
              InkWell(
                onTap: () => _openContact(t.orderingContact),
                child: Text(
                  'Objednávky: ${t.orderingContact}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            if (t.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(t.notes,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }

  void _openContact(String contact) {
    final Uri uri;
    if (contact.contains('@')) {
      uri = Uri.parse('mailto:$contact');
    } else if (RegExp(r'^[+0-9 ]+$').hasMatch(contact)) {
      uri = Uri.parse('tel:${contact.replaceAll(' ', '')}');
    } else {
      uri = Uri.parse(
          contact.startsWith('http') ? contact : 'https://$contact');
    }
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _DayRow extends ConsumerWidget {
  const _DayRow({
    required this.day,
    required this.slots,
    required this.heatmap,
    required this.uid,
  });

  final Day day;
  final List<Slot> slots;
  final Heatmap heatmap;
  final String? uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayStats = heatmap.byDay[day];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(dayLabel(day),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 8),
              if (dayStats != null && dayStats.distinctPlayers > 0)
                Text('${dayStats.distinctPlayers} lidí může',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final slot in slots) _cell(context, slot)],
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, Slot slot) {
    final stats = heatmap.bySlotId[slot.id];
    final mine = uid != null && (stats?.userIds.contains(uid) ?? false);

    return SlotCell(
      time: slot.time,
      count: stats?.count ?? 0,
      intensity: heatmap.intensity(slot.id),
      isOrderable: stats?.isOrderable ?? false,
      mine: mine,
      onTap: () => Api.setAvailability(slot.id, !mine),
      onLongPress: () => _confirmDelete(context, slot),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Slot slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Smazat start?'),
        content: Text('${dayFull(slot.date)} ${slot.time.display()} — '
            'včetně hlasů a obsazení.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Ne')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Smazat')),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await tryAction(context, () => Api.deleteSlot(slot.id));
    }
  }
}

class _BestPicksCard extends StatelessWidget {
  const _BestPicksCard({required this.tournament, required this.heatmap});

  final Tournament tournament;
  final Heatmap heatmap;

  @override
  Widget build(BuildContext context) {
    final picks = bestPicks(heatmap: heatmap);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nejsilnější termíny',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (picks.isEmpty)
              const Text('Zatím se nikde nesešlo dost hráčů. '
                  'Odklikejte si termíny!')
            else
              for (final p in picks)
                Text('• ${dayLabel(p.slot.date)} ${p.slot.time.display()} — '
                    '${p.count} hráčů'),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.how_to_vote),
                  label: const Text('Navrhnout'),
                  onPressed: () => _openProposal(context, direct: false),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => _openProposal(context, direct: true),
                  child: const Text('Objednat rovnou'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openProposal(BuildContext context, {required bool direct}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProposalScreen(
        tournament: tournament,
        preselected: {for (final s in suggestedBundle(heatmap)) s.slot.id},
        directlyOrdered: direct,
      ),
    ));
  }
}
