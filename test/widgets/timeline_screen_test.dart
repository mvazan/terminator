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
    List<Order> orders = const [],
    Map<String, Map<String, int>> orderSlots = const {},
  }) =>
      ProviderScope(
        overrides: [
          allTournamentsProvider
              .overrideWithValue(AsyncValue.data(tournaments ?? [tournament])),
          myHiddenTournamentsProvider
              .overrideWithValue(AsyncValue.data(myHidden)),
          slotsProvider.overrideWithValue(AsyncValue.data(slots)),
          ordersProvider.overrideWithValue(AsyncValue.data(orders)),
          orderSlotsProvider.overrideWithValue(AsyncValue.data(orderSlots)),
          venueNamesProvider.overrideWithValue({'v1': 'Vracov'}),
        ],
        child: const MaterialApp(home: TimelineScreen()),
      );

  Finder opaqueBoxes() =>
      find.byWidgetPredicate((w) => w is ColoredBox && w.color.a == 1.0);

  testWidgets('draws a visible, day-proportional bar', (tester) async {
    await tester.pumpWidget(wrap());

    final bar = opaqueBoxes();
    expect(bar, findsOneWidget);
    final size = tester.getSize(bar);
    expect(size.height, greaterThan(20)); // fills the cell vertically
    // 3/7 of the 84 px cell.
    expect(size.width, closeTo(84 * 3 / 7, 2.0));
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

  testWidgets('start and ordered days render distinct vertical markers',
      (tester) async {
    final slot = makeSlot(
      's1',
      Day(2026, 4, 24), // Friday, dayIndex 4
      const HourMinute(17, 0),
      tournamentId: tournament.id,
    );
    await tester.pumpWidget(wrap(slots: [slot]));

    // One bar + one 2px start marker (black54 is not fully opaque, so it is
    // not matched by opaqueBoxes).
    final marker = find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == Colors.black54);
    expect(marker, findsOneWidget);
    expect(tester.getSize(marker).width, 2);

    // Make the day ordered -> the marker turns red.
    final order = makeOrder(id: 'o1', tournamentId: tournament.id);
    await tester.pumpWidget(wrap(
      slots: [slot],
      orders: [order],
      orderSlots: {
        'o1': {'s1': 1},
      },
    ));
    await tester.pump();

    expect(
      find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == const Color(0xFFD32F2F)),
      findsOneWidget,
    );
  });
}
