import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/busy.dart';
import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/commitments.dart';
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
  const OrderCard({
    super.key,
    required this.order,
    required this.tournament,
    this.readOnly = false,
  });

  final Order order;
  final Tournament tournament;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider).value ?? const [];
    final lanesBySlot =
        ref.watch(orderSlotsProvider).value?[order.id] ??
            const <String, int>{};
    final slots = (ref.watch(slotsProvider).value ?? const [])
        .where((s) => lanesBySlot.containsKey(s.id))
        .toList()
      ..sort(Slot.compare);
    final votes = (ref.watch(orderVotesProvider).value ?? const [])
        .where((v) => v.orderId == order.id)
        .toList();
    final rosters = (ref.watch(rostersProvider).value ?? const [])
        .where((r) => lanesBySlot.containsKey(r.slotId))
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
                        : 'Objednáno — $creator',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (!readOnly) _menu(context),
              ],
            ),
            Text(daysLabel),
            if (order.note.isNotEmpty)
              Text(order.note, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            if (order.isProposal)
              _ProposalVoting(
                order: order,
                votes: votes,
                members: members,
                readOnly: readOnly,
              )
            else
              _OrderedBody(
                tournament: tournament,
                slots: slots,
                lanesBySlot: lanesBySlot,
                rosters: rosters,
                members: members,
                readOnly: readOnly,
              ),
          ],
        ),
      ),
    );
  }

  String _slotsSummary(List<Slot> slots) {
    final byDay = slotsByDay(slots);
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
        const PopupMenuItem(value: 'cancel', child: Text('Zrušit')),
      ],
    );
  }
}

class _ProposalVoting extends StatefulWidget {
  const _ProposalVoting({
    required this.order,
    required this.votes,
    required this.members,
    this.readOnly = false,
  });

  final Order order;
  final List<OrderVote> votes;
  final List<Profile> members;
  final bool readOnly;

  @override
  State<_ProposalVoting> createState() => _ProposalVotingState();
}

class _ProposalVotingState extends State<_ProposalVoting> {
  /// Vote write in flight — disables the segments against double-fires.
  bool _voting = false;

  Order get order => widget.order;
  List<OrderVote> get votes => widget.votes;
  List<Profile> get members => widget.members;
  bool get readOnly => widget.readOnly;

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
          onSelectionChanged: readOnly || _voting
              ? null
              : (selection) async {
                  if (selection.isEmpty) return;
                  setState(() => _voting = true);
                  try {
                    await tryAction(
                        context, () => Api.vote(order.id, selection.first));
                  } finally {
                    if (mounted) setState(() => _voting = false);
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
    required this.lanesBySlot,
    required this.rosters,
    required this.members,
    this.readOnly = false,
  });

  final Tournament tournament;
  final List<Slot> slots;
  final Map<String, int> lanesBySlot;
  final List<RosterEntry> rosters;
  final List<Profile> members;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = orderPlaces(
        tournament: tournament,
        orderSlots: slots,
        rosters: rosters,
        lanesBySlot: lanesBySlot);
    final uid = currentUserId;
    final days = {for (final s in slots) s.date};

    // Who ticked each slot in "Kdy můžeš?" — the add-player sheet offers
    // them first.
    final availability = ref.watch(availabilityProvider).value ?? const [];
    final tickedBySlot = <String, Set<String>>{};
    for (final a in availability) {
      tickedBySlot.putIfAbsent(a.slotId, () => {}).add(a.userId);
    }

    // Same-day "you're already playing elsewhere" data for the ⚠️ guard.
    final commitments = ref.watch(commitmentsProvider);
    final venueNames = ref.watch(venueNamesProvider);
    String venueOf(String tournamentId) {
      final t = ref.watch(tournamentByIdProvider(tournamentId));
      return t == null ? '?' : (venueNames[t.venueId] ?? '?');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Objednáno ${lanesLabel(places.orderedLanes)}'
          '${tournament.kind.playersPerLane > 1 ? ' (${places.orderedPlaces} míst)' : ''} · '
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
            ticked: tickedBySlot[slotPlaces.slot.id] ?? const {},
            uid: uid,
            readOnly: readOnly,
            commitments: commitments,
            venueOf: venueOf,
          ),
        const SizedBox(height: 8),
        // Day chats are closed groups — offer the shortcut only to people
        // actually assigned on this order.
        if (rosters.any((r) => r.userId == uid))
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
    required this.ticked,
    required this.uid,
    this.readOnly = false,
    this.commitments = const [],
    required this.venueOf,
  });

  final SlotPlaces slotPlaces;
  final List<RosterEntry> rosters;
  final List<Profile> members;

  /// User ids who ticked this slot in "Kdy můžeš?".
  final Set<String> ticked;

  final String? uid;
  final bool readOnly;

  /// All active-order commitments — to warn when the person being added is
  /// already playing elsewhere that day. `venueOf` labels a tournament.
  final List<Commitment> commitments;
  final String Function(String tournamentId) venueOf;

  /// True to proceed: no same-day clash, or the user confirmed the ⚠️.
  Future<bool> _okToAdd(BuildContext context, String userId) async {
    final clashes = conflictsFor(commitments,
        userId: userId,
        day: slotPlaces.slot.date,
        exceptSlotId: slotPlaces.slot.id);
    if (clashes.isEmpty) return true;
    final name = memberName(members, userId);
    final where = clashes
        .map((c) => '${venueOf(c.tournamentId)} ${c.time.display()}')
        .join(', ');
    return confirmDialog(
      context,
      title: '⚠️ Hraje jinde',
      message: '$name už v tento den hraje: $where. Přidat i sem?',
      confirmLabel: 'Přidat i tak',
    );
  }

  @override
  Widget build(BuildContext context) {
    final slot = slotPlaces.slot;
    final imIn = rosters.any((r) => r.userId == uid);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${dayLabel(slot.date)} ${slot.time.display()} · '
              '${slotPlaces.filled}/${slotPlaces.capacity} hráčů'),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final entry in rosters)
                InputChip(
                  label: Text(rosterEntryName(entry, members)),
                  onDeleted: readOnly
                      ? null
                      : () => tryAction(
                          context, () => Api.removeRosterEntry(entry.id)),
                ),
              if (!readOnly && slotPlaces.hasFreePlace) ...[
                if (!imIn)
                  BusyActionChip(
                    avatar: const Icon(Icons.person_add, size: 16),
                    label: const Text('Přidám se'),
                    onPressed: () async {
                      if (uid != null && !await _okToAdd(context, uid!)) {
                        return;
                      }
                      if (!context.mounted) return;
                      await tryAction(
                          context, () => Api.joinSlot(slot.id));
                    },
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

  /// Adds [userId] to this start after the same-day ⚠️ guard.
  Future<void> _addMember(BuildContext context, String userId) async {
    if (!await _okToAdd(context, userId)) return;
    if (!context.mounted) return;
    await tryAction(
        context, () => Api.joinSlot(slotPlaces.slot.id, userId: userId));
  }

  Future<void> _addSomeone(BuildContext context) async {
    final inSlot = {for (final r in rosters) r.userId};
    final candidates = [
      for (final m in members)
        if (m.isApproved && !inSlot.contains(m.id)) m,
    ];
    // Those who ticked this slot in "Kdy můžeš?" go first.
    final signedUp = [for (final m in candidates) if (ticked.contains(m.id)) m];
    final others = [for (final m in candidates) if (!ticked.contains(m.id)) m];

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
            for (final m in signedUp)
              ListTile(
                leading: const Icon(Icons.event_available),
                title: Text(m.displayName),
                subtitle: const Text('hlásí se na tento start'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _addMember(context, m.id);
                },
              ),
            if (signedUp.isNotEmpty && others.isNotEmpty)
              const Divider(height: 1),
            for (final m in others)
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(m.displayName),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _addMember(context, m.id);
                },
              ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Host (nemá appku) — zadat jméno'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final name = await promptText(context,
                    title: 'Jméno hosta',
                    hint: 'např. Franta',
                    confirmLabel: 'Přidat');
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
}
