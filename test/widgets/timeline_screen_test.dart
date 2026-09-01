import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/data/providers.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/features/tournaments/timeline_screen.dart';

import '../domain/helpers.dart';

void main() {
  // 24.–26. 4. 2026 is Fri–Sun: one week column, bar = right 3/7 of it.
  final tournament = makeTournament(
    startsOn: Day(2026, 4, 24),
    endsOn: Day(2026, 4, 26),
  );

  Widget wrap({
    List<Tournament>? tournaments,
    Set<String> myHidden = const {},
    List<Slot> slots = const [],
    List<Availability> availability = const [],
    List<Order> orders = const [],
    Map<String, Map<String, int>> orderSlots = const {},
    List<RosterEntry> rosters = const [],
    Day? today,
  }) =>
      ProviderScope(
        overrides: [
          allTournamentsProvider
              .overrideWithValue(AsyncValue.data(tournaments ?? [tournament])),
          myHiddenTournamentsProvider
              .overrideWithValue(AsyncValue.data(myHidden)),
          slotsProvider.overrideWithValue(AsyncValue.data(slots)),
          availabilityProvider
              .overrideWithValue(AsyncValue.data(availability)),
          ordersProvider.overrideWithValue(AsyncValue.data(orders)),
          orderSlotsProvider.overrideWithValue(AsyncValue.data(orderSlots)),
          rostersProvider.overrideWithValue(AsyncValue.data(rosters)),
          venueNamesProvider.overrideWithValue({'v1': 'Vracov'}),
          currentUserIdProvider.overrideWithValue('me'),
        ],
        // Fixed "today" before the fixture tournament, so the
        // ended-tournament filter never hides it as the real date moves on.
        child: MaterialApp(
            home: TimelineScreen(today: today ?? Day(2026, 4, 20))),
      );

  // Bars and markers are opaque; the today band is translucent by design
  // (data must stay readable through it), so it never matches this finder.
  Finder opaqueBoxes() =>
      find.byWidgetPredicate((w) => w is ColoredBox && w.color.a == 1.0);
  Finder todayBand() => find.byWidgetPredicate((w) =>
      w is ColoredBox && w.color.toARGB32() == 0x381565C0);

  testWidgets('draws a visible, day-proportional bar', (tester) async {
    await tester.pumpWidget(wrap());

    final bar = opaqueBoxes();
    expect(bar, findsOneWidget);
    final size = tester.getSize(bar);
    expect(size.height, greaterThan(20)); // fills the cell vertically
    // 3/7 of the 84 px cell.
    expect(size.width, closeTo(84 * 3 / 7, 2.0));
  });

  testWidgets('ended tournament is hidden by default, shown via the toggle',
      (tester) async {
    // Fixture ends 26. 4. — a "today" after that makes it ended.
    await tester.pumpWidget(wrap(today: Day(2026, 5, 1)));
    expect(opaqueBoxes(), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();
    expect(opaqueBoxes(), findsOneWidget);
  });

  testWidgets('my-hidden tournament is only shown via the toggle, in gray',
      (tester) async {
    await tester.pumpWidget(wrap(myHidden: {tournament.id}));

    // Toggle off: hidden row absent entirely.
    expect(opaqueBoxes(), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();

    final bar = tester.widget<ColoredBox>(opaqueBoxes());
    expect(bar.color, const Color(0xFFBDBDBD));
  });

  testWidgets('today band covers the current day, only inside shown weeks',
      (tester) async {
    // Default fixture today = Monday 20. 4. = day 0 of the single week
    // column: the band fills that whole day-seventh (84 / 7 = 12 px) right
    // after the label (140), plus the 12 px scroll padding.
    await tester.pumpWidget(wrap());
    expect(todayBand(), findsOneWidget);
    expect(tester.getSize(todayBand()).width, closeTo(84 / 7, 0.01));
    expect(tester.getTopLeft(todayBand()).dx, closeTo(12 + 140, 0.5));

    // The word "dnes" flags the band's top, centered on the day (wider
    // than the 12 px band on purpose).
    expect(find.text('dnes'), findsOneWidget);
    final bandCenterX = tester.getCenter(todayBand()).dx;
    expect(tester.getCenter(find.text('dnes')).dx, closeTo(bandCenterX, 0.5));

    // Today before the shown weeks (future tournament) → no band, no flag.
    await tester.pumpWidget(wrap(today: Day(2026, 4, 13)));
    await tester.pump();
    expect(todayBand(), findsNothing);
    expect(find.text('dnes'), findsNothing);
  });

  testWidgets('venue-full days lose the interest tick, never the order mark',
      (tester) async {
    // My ticked start has no free lanes left — the grey tick is moot
    // (nothing to order there anymore).
    final full = makeSlot('s1', Day(2026, 4, 24), const HourMinute(17, 0),
        tournamentId: tournament.id, venueCapacity: 8, venueOccupied: 8);
    const myTick = Availability(slotId: 's1', userId: 'me');
    final grey = find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == Colors.black54);
    await tester.pumpWidget(wrap(slots: [full], availability: [myTick]));
    expect(grey, findsNothing);

    // Another ticked start the same day still bookable → the day keeps
    // its tick.
    final free = makeSlot('s2', Day(2026, 4, 24), const HourMinute(19, 0),
        tournamentId: tournament.id, venueCapacity: 8, venueOccupied: 2);
    await tester.pumpWidget(wrap(
      slots: [full, free],
      availability: [myTick, const Availability(slotId: 's2', userId: 'me')],
    ));
    await tester.pump();
    expect(grey, findsOneWidget);

    // Orders are OURS — the red mark stays even where we ate the capacity.
    await tester.pumpWidget(wrap(
      slots: [full],
      availability: [myTick],
      orders: [makeOrder(id: 'o1', tournamentId: tournament.id)],
      orderSlots: {
        'o1': {'s1': 1},
      },
      rosters: [
        const RosterEntry(id: 'r1', slotId: 's1', addedBy: 'me', userId: 'me'),
      ],
    ));
    await tester.pump();
    expect(
        find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == const Color(0xFFD32F2F)),
        findsOneWidget);
    expect(grey, findsNothing);
  });

  testWidgets('my ticks and ordered days render distinct vertical markers',
      (tester) async {
    final slot = makeSlot(
      's1',
      Day(2026, 4, 24), // Friday, dayIndex 4
      const HourMinute(17, 0),
      tournamentId: tournament.id,
    );
    const myTick = Availability(slotId: 's1', userId: 'me');
    await tester.pumpWidget(wrap(slots: [slot], availability: [myTick]));

    // One bar + one 2px tick marker (black54 is not fully opaque, so it is
    // not matched by opaqueBoxes).
    final marker = find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == Colors.black54);
    expect(marker, findsOneWidget);
    expect(tester.getSize(marker).width, 2);

    // A team order alone does NOT paint my calendar red…
    final order = makeOrder(id: 'o1', tournamentId: tournament.id);
    await tester.pumpWidget(wrap(
      slots: [slot],
      availability: [myTick],
      orders: [order],
      orderSlots: {
        'o1': {'s1': 1},
      },
    ));
    await tester.pump();
    Finder red() => find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == const Color(0xFFD32F2F));
    expect(red(), findsNothing);

    // …only a day where I'M on the roster does.
    await tester.pumpWidget(wrap(
      slots: [slot],
      availability: [myTick],
      orders: [order],
      orderSlots: {
        'o1': {'s1': 1},
      },
      rosters: [
        const RosterEntry(
            id: 'r1', slotId: 's1', addedBy: 'me', userId: 'me'),
      ],
    ));
    await tester.pump();
    expect(red(), findsOneWidget);
  });
}
