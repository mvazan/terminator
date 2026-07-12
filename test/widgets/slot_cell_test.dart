import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/features/tournaments/slot_cell.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  Border borderOf(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.descendant(
          of: find.byType(SlotCell), matching: find.byType(Container)),
    );
    return (container.decoration! as BoxDecoration).border! as Border;
  }

  testWidgets('shows time and player count, no decorations', (tester) async {
    await tester.pumpWidget(wrap(SlotCell(
      time: const HourMinute(18, 0),
      count: 4,
      intensity: 1,
      isOrderable: false,
      mine: false,
      onTap: () {},
    )));

    expect(find.text('18:00'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(borderOf(tester).top.width, 1);
  });

  testWidgets('my selection gets the thick border and fires onTap',
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

    // Mine = thick border, NOT the check icon (that means "enough people").
    expect(borderOf(tester).top.width, 2);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    await tester.tap(find.text('16:30'));
    expect(taps, 1);
  });

  testWidgets('enough-people cell shows the check with a thin border',
      (tester) async {
    await tester.pumpWidget(wrap(SlotCell(
      time: const HourMinute(17, 0),
      count: 3,
      intensity: 0.7,
      isOrderable: true,
      mine: false,
      onTap: () {},
    )));

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(borderOf(tester).top.width, 1);
  });

  testWidgets('venue-full cell keeps the error border even when mine',
      (tester) async {
    const theme = ColorScheme.light();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: theme),
      home: Scaffold(
        body: Center(
          child: SlotCell(
            time: const HourMinute(18, 0),
            count: 2,
            intensity: 0.5,
            isOrderable: false,
            mine: true,
            venueFree: 0,
            onTap: () {},
          ),
        ),
      ),
    ));

    final border = borderOf(tester);
    expect(border.top.color, theme.error);
    expect(border.top.width, 1); // full cell never gets the thick border
  });

  testWidgets('scraped cell shows team/free lanes as X/Y', (tester) async {
    await tester.pumpWidget(wrap(SlotCell(
      time: const HourMinute(18, 0),
      count: 6, // team can exceed venue capacity
      intensity: 0.5,
      isOrderable: true,
      mine: false,
      onTap: () {},
      venueFree: 4,
    )));

    expect(find.text('6/4'), findsOneWidget);
    expect(find.text('6'), findsNothing);
  });

  testWidgets('non-scraped cell shows just the team count', (tester) async {
    await tester.pumpWidget(wrap(SlotCell(
      time: const HourMinute(18, 0),
      count: 3,
      intensity: 0.5,
      isOrderable: false,
      mine: false,
      onTap: () {},
    )));

    expect(find.text('3'), findsOneWidget);
    // Only the time and count texts — no venue slash line.
    expect(find.byType(Text), findsNWidgets(2));
  });

  testWidgets('null onTap makes the cell inert (read-only)', (tester) async {
    await tester.pumpWidget(wrap(const SlotCell(
      time: HourMinute(18, 0),
      count: 2,
      intensity: 0.5,
      isOrderable: true,
      mine: false,
    )));

    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.onTap, isNull);
  });
}
