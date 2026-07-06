import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import '../../domain/places.dart';
import '../chats/chat_screen.dart';

/// One proposal/order in the tournament detail.
///
/// Proposal: slots summary + Beru / Nemůžu / Radši jiný den voting + tally;
/// anyone can convert it to "ordered" (after actually ordering by
/// e-mail/phone) or cancel it.
/// Ordered: per-slot rosters — join, assign members, add guests, free places.
class OrderCard extends ConsumerWidget {
  const OrderCard({super.key, required this.order, required this.tournament});

  final Order order;
  final Tournament tournament;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider).value ?? const [];
    final slotIdsOfOrder =
        ref.watch(orderSlotsProvider).value?[order.id] ?? const <String>{};
    final slots = (ref.watch(slotsProvider).value ?? const [])
        .where((s) => slotIdsOfOrder.contains(s.id))
        .toList()
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        return a.time.compareTo(b.time);
      });
    final votes = (ref.watch(orderVotesProvider).value ?? const [])
        .where((v) => v.orderId == order.id)
        .toList();
    final rosters = (ref.watch(rostersProvider).value ?? const [])
        .where((r) => slotIdsOfOrder.contains(r.slotId))
        .toList();

    final creator = memberName(members, order.createdBy);
    final daysLabel = _slotsSummary(slots);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  order.isProposal ? Icons.how_to_vote : Icons.receipt_long,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.isProposal
                        ? 'Návrh — $creator'
                        : 'Objednáno — $creator'
                            '${order.status == OrderStatus.confirmed ? ' ✓ potvrzeno' : ''}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                _menu(context),
              ],
            ),
            Text(daysLabel),
            if (order.note.isNotEmpty)
              Text(order.note, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            if (order.isProposal)
              _ProposalVoting(order: order, votes: votes, members: members)
            else
              _OrderedBody(
                tournament: tournament,
                slots: slots,
                rosters: rosters,
                members: members,
              ),
          ],
        ),
      ),
    );
  }

  String _slotsSummary(List<Slot> slots) {
    final byDay = <Day, List<Slot>>{};
    for (final s in slots) {
      byDay.putIfAbsent(s.date, () => []).add(s);
    }
    return [
      for (final day in byDay.keys)
        '${dayLabel(day)} '
            '${byDay[day]!.map((s) => s.time.display()).join(' + ')}',
    ].join(' · ');
  }

  Widget _menu(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (action) async {
        switch (action) {
          case 'ordered':
            await tryAction(
                context, () => Api.setOrderStatus(order.id, OrderStatus.ordered),
                success: 'Označeno jako objednané.');
          case 'confirmed':
            await tryAction(context,
                () => Api.setOrderStatus(order.id, OrderStatus.confirmed),
                success: 'Potvrzeno.');
          case 'cancel':
            await tryAction(context,
                () => Api.setOrderStatus(order.id, OrderStatus.cancelled),
                success: 'Zrušeno.');
        }
      },
      itemBuilder: (_) => [
        if (order.isProposal)
          const PopupMenuItem(
              value: 'ordered', child: Text('Objednal(a) jsem to ✓')),
        if (order.status == OrderStatus.ordered)
          const PopupMenuItem(
              value: 'confirmed', child: Text('Pořadatel potvrdil')),
        const PopupMenuItem(value: 'cancel', child: Text('Zrušit')),
      ],
    );
  }
}

class _ProposalVoting extends StatelessWidget {
  const _ProposalVoting({
    required this.order,
    required this.votes,
    required this.members,
  });

  final Order order;
  final List<OrderVote> votes;
  final List<Profile> members;

  @override
  Widget build(BuildContext context) {
    final uid = currentUserId;
    final myVote = votes.where((v) => v.userId == uid).firstOrNull?.vote;

    String names(Vote vote) => votes
        .where((v) => v.vote == vote)
        .map((v) => memberName(members, v.userId))
        .join(', ');
    int count(Vote vote) => votes.where((v) => v.vote == vote).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<Vote>(
          segments: const [
            ButtonSegment(value: Vote.inn, label: Text('Beru')),
            ButtonSegment(value: Vote.out, label: Text('Nemůžu')),
            ButtonSegment(value: Vote.otherDay, label: Text('Jiný den')),
          ],
          emptySelectionAllowed: true,
          selected: {?myVote},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              tryAction(context, () => Api.vote(order.id, selection.first));
            }
          },
        ),
        const SizedBox(height: 8),
        for (final (vote, label) in [
          (Vote.inn, 'Beru'),
          (Vote.out, 'Nemůžu'),
          (Vote.otherDay, 'Radši jiný den'),
        ])
          if (count(vote) > 0)
            Text('$label (${count(vote)}): ${names(vote)}',
                style: Theme.of(context).textTheme.bodySmall),
        if (votes.isEmpty)
          Text('Zatím nikdo nehlasoval.',
              style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _OrderedBody extends ConsumerWidget {
  const _OrderedBody({
    required this.tournament,
    required this.slots,
    required this.rosters,
    required this.members,
  });

  final Tournament tournament;
  final List<Slot> slots;
  final List<RosterEntry> rosters;
  final List<Profile> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = orderPlaces(
        tournament: tournament, orderSlots: slots, rosters: rosters);
    final uid = currentUserId;
    final days = {for (final s in slots) s.date};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (places.orderedPlaces != null)
          Text(
            'Objednáno ${places.orderedPlaces} míst · '
            'obsazeno ${places.filledPlaces} · '
            'volných ${places.freePlaces}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        const SizedBox(height: 4),
        for (final slotPlaces in places.perSlot)
          _SlotRoster(
            slotPlaces: slotPlaces,
            rosters: [
              for (final r in rosters)
                if (r.slotId == slotPlaces.slot.id) r,
            ],
            members: members,
            uid: uid,
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final day in days)
              ActionChip(
                avatar: const Icon(Icons.chat_bubble_outline, size: 16),
                label: Text('Chat ${dayLabel(day)}'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                        tournamentId: tournament.id, day: day),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SlotRoster extends StatelessWidget {
  const _SlotRoster({
    required this.slotPlaces,
    required this.rosters,
    required this.members,
    required this.uid,
  });

  final SlotPlaces slotPlaces;
  final List<RosterEntry> rosters;
  final List<Profile> members;
  final String? uid;

  @override
  Widget build(BuildContext context) {
    final slot = slotPlaces.slot;
    final imIn = rosters.any((r) => r.userId == uid);
    final capacityLabel = slotPlaces.capacity == null
        ? '${slotPlaces.filled}'
        : '${slotPlaces.filled}/${slotPlaces.capacity}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${dayLabel(slot.date)} ${slot.time.display()} · '
              '$capacityLabel hráčů'),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final entry in rosters)
                InputChip(
                  label: Text(rosterEntryName(entry, members)),
                  onDeleted: () => tryAction(
                      context, () => Api.removeRosterEntry(entry.id)),
                ),
              if (slotPlaces.hasFreePlace) ...[
                if (!imIn)
                  ActionChip(
                    avatar: const Icon(Icons.person_add, size: 16),
                    label: const Text('Přidám se'),
                    onPressed: () =>
                        tryAction(context, () => Api.joinSlot(slot.id)),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.group_add, size: 16),
                  label: const Text('Přidat…'),
                  onPressed: () => _addSomeone(context),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addSomeone(BuildContext context) async {
    final inSlot = {for (final r in rosters) r.userId};
    final candidates = [
      for (final m in members)
        if (m.isApproved && !inSlot.contains(m.id)) m,
    ];

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Koho přidat na tento start?'),
            ),
            for (final m in candidates)
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(m.displayName),
                onTap: () {
                  Navigator.pop(sheetContext);
                  tryAction(context,
                      () => Api.joinSlot(slotPlaces.slot.id, userId: m.id));
                },
              ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Host (nemá appku) — zadat jméno'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final name = await _askGuestName(context);
                if (name != null && name.isNotEmpty && context.mounted) {
                  await tryAction(
                      context, () => Api.addGuest(slotPlaces.slot.id, name));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askGuestName(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Jméno hosta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'např. Franta'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Zrušit')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Přidat'),
          ),
        ],
      ),
    );
  }
}
