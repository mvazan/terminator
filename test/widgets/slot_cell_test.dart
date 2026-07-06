import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/features/tournaments/slot_cell.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('shows time and player count', (tester) async {
    await tester.pumpWidget(wrap(SlotCell(
      time: const HourMinute(18, 0),
      count: 4,
      intensity: 1,
      isOrderable: true,
      mine: false,
      onTap: () {},
    )));

    expect(find.text('18:00'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('shows my tick and fires onTap (toggle availability)',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(SlotCell(
      time: const HourMinute(16, 30),
      count: 2,
      intensity: 0.5,
      isOrderable: false,
      mine: true,
      onTap: () => taps++,
    )));

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tester.tap(find.text('16:30'));
    expect(taps, 1);
  });

  testWidgets('orderable cell gets the thick primary border', (tester) async {
    await tester.pumpWidget(wrap(SlotCell(
      time: const HourMinute(17, 0),
      count: 3,
      intensity: 0.7,
      isOrderable: true,
      mine: false,
      onTap: () {},
    )));

    final container = tester.widget<Container>(
      find.descendant(
          of: find.byType(SlotCell), matching: find.byType(Container)),
    );
    final border = (container.decoration! as BoxDecoration).border! as Border;
    expect(border.top.width, 2);
  });

  testWidgets('shows expand chevron only when someone is in, and toggles it',
      (tester) async {
    var toggles = 0;
    await tester.pumpWidget(wrap(SlotCell(
      time: const HourMinute(18, 0),
      count: 3,
      intensity: 0.5,
      isOrderable: true,
      mine: false,
      onTap: () {},
      onToggleExpand: () => toggles++,
    )));

    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    await tester.tap(find.byIcon(Icons.expand_more));
    expect(toggles, 1);
  });

  testWidgets('no expand chevron when nobody ticked the slot',
      (tester) async {
    await tester.pumpWidget(wrap(SlotCell(
      time: const HourMinute(18, 0),
      count: 0,
      intensity: 0,
      isOrderable: false,
      mine: false,
      onTap: () {},
      onToggleExpand: () {},
    )));

    expect(find.byIcon(Icons.expand_more), findsNothing);
    expect(find.byIcon(Icons.expand_less), findsNothing);
  });

  testWidgets('expanded shows the "less" chevron', (tester) async {
    await tester.pumpWidget(wrap(SlotCell(
      time: const HourMinute(18, 0),
      count: 2,
      intensity: 0.5,
      isOrderable: false,
      mine: false,
      onTap: () {},
      expanded: true,
      onToggleExpand: () {},
    )));

    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });
}
