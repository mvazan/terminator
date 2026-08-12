import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/core/ui.dart';
import 'package:terminator/data/providers.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/features/home/my_starts_screen.dart';

import '../domain/helpers.dart';

void main() {
  final sat = Day(2026, 9, 5);
  final tournament = makeTournament(startsOn: sat, endsOn: sat);
  const venue = Venue(
      id: 'v1',
      name: 'Vracov',
      laneCount: 4,
      address: '',
      sourceUrl: '');
  final s1 = makeSlot('s1', sat, const HourMinute(17, 0));
  final s2 = makeSlot('s2', sat, const HourMinute(19, 0));

  Widget wrap({
    List<Order> orders = const [],
    Map<String, Map<String, int>> orderSlots = const {},
    List<RosterEntry> rosters = const [],
  }) =>
      ProviderScope(
        overrides: [
          tournamentsProvider
              .overrideWithValue(AsyncValue.data([tournament])),
          venuesProvider.overrideWithValue(const AsyncValue.data([venue])),
          slotsProvider.overrideWithValue(AsyncValue.data([s1, s2])),
          ordersProvider.overrideWithValue(AsyncValue.data(orders)),
          orderSlotsProvider.overrideWithValue(AsyncValue.data(orderSlots)),
          rostersProvider.overrideWithValue(AsyncValue.data(rosters)),
          membersProvider.overrideWithValue(const AsyncValue.data([])),
          availabilityProvider.overrideWithValue(const AsyncValue.data([])),
          currentUserIdProvider.overrideWithValue('me'),
        ],
        // Fixed "today" before the fixtures so they never age out.
        child: MaterialApp(home: MyStartsScreen(today: Day(2026, 9, 1))),
      );

  // Tap navigation is deliberately not asserted: TournamentDetailScreen reads
  // the raw currentUserId getter (Supabase.instance asserts in tests) and the
  // scrollToOrders mechanics are already exercised by the chat context bar.

  testWidgets('open order renders the Volná místa row with declined count',
      (tester) async {
    // Order on both starts, 1 lane each; I'm on s1 (full), s2 stays free.
    await tester.pumpWidget(wrap(
      orders: [makeOrder()],
      orderSlots: {
        'o1': {'s1': 1, 's2': 1},
      },
      rosters: [
        const RosterEntry(
            id: 'r1', slotId: 's1', addedBy: 'me', userId: 'me'),
      ],
    ));

    // My start renders as the hero…
    expect(find.textContaining('Nejbližší start'), findsOneWidget);
    // …and the free place on 19:00 shows in the section.
    expect(find.text('Volná místa'), findsOneWidget);
    expect(find.textContaining('19:00'), findsOneWidget);
    expect(find.textContaining('1 volné místo'), findsOneWidget);
    expect(find.byType(DateBadge), findsWidgets);
  });

  testWidgets('full order → no section header', (tester) async {
    await tester.pumpWidget(wrap(
      orders: [makeOrder()],
      orderSlots: {
        'o1': {'s1': 1, 's2': 1},
      },
      rosters: [
        const RosterEntry(
            id: 'r1', slotId: 's1', addedBy: 'me', userId: 'me'),
        const RosterEntry(
            id: 'r2', slotId: 's2', addedBy: 'me', userId: 'u2'),
      ],
    ));
    expect(find.textContaining('Nejbližší start'), findsOneWidget);
    expect(find.text('Volná místa'), findsNothing);
  });

  testWidgets('proposal only → empty state, no section', (tester) async {
    await tester.pumpWidget(wrap(
      orders: [makeOrder(status: OrderStatus.proposed)],
      orderSlots: {
        'o1': {'s1': 1},
      },
    ));
    expect(find.textContaining('Zatím nikde nehraješ'), findsOneWidget);
    expect(find.text('Volná místa'), findsNothing);
  });
}
