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

  testWidgets('venue-full-by-US cell is friendly: home icon, no error border',
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
            mine: false,
            venueFree: 0,
            venueOurs: 4, // we booked all the lanes ourselves
            onTap: () {},
          ),
        ),
      ),
    ));

    expect(find.byIcon(Icons.home), findsOneWidget);
    final border = borderOf(tester);
    expect(border.top.color, isNot(theme.error)); // not the blocked look
    // Time is not struck through.
    final timeText = tester.widget<Text>(find.text('18:00'));
    expect(timeText.style?.decoration, isNot(TextDecoration.lineThrough));
  });

  testWidgets(
      'ordered cell: green border+background, ordinary numbers stay',
      (tester) async {
    await tester.pumpWidget(wrap(SlotCell(
      time: const HourMinute(17, 30),
      count: 2, // waiting ticks — the caller already subtracted assigned
      intensity: 0.5,
      isOrderable: true, // would show ✓ — the order supersedes it
      mine: false,
      venueFree: 2,
      venueOurs: 5,
      ordered: true,
      onTap: () {},
    )));

    // Same info as any scraped cell: waiting/free — NOT the order's X/Y.
    expect(find.text('2/2'), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget); // our venue booking
    expect(find.byIcon(Icons.check_circle), findsNothing);
    final container = tester.widget<Container>(
      find.descendant(
          of: find.byType(SlotCell), matching: find.byType(Container)),
    );
    final decoration = container.decoration! as BoxDecoration;
    final border = decoration.border! as Border;
    expect(border.top.color, Colors.green);
    expect(border.top.width, 2);
    // The background leaves the heat scale for a soft green.
    final scheme = ThemeData.light().colorScheme;
    expect(decoration.color,
        Color.lerp(scheme.surfaceContainerHighest, Colors.green, 0.18));
  });

  testWidgets('ordered cell without venue info shows the plain count',
      (tester) async {
    await tester.pumpWidget(wrap(SlotCell(
      time: const HourMinute(17, 30),
      count: 1,
      intensity: 0,
      isOrderable: false,
      mine: false,
      ordered: true, // manual tournament — no venue info at all
      onTap: () {},
    )));

    expect(find.byIcon(Icons.home), findsNothing); // no venue booking
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('ordered wins over the foreign-full blocked look',
      (tester) async {
    const theme = ColorScheme.light();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: theme),
      home: Scaffold(
        body: Center(
          child: SlotCell(
            time: const HourMinute(18, 0),
            count: 0,
            intensity: 0,
            isOrderable: false,
            mine: false,
            venueFree: 0,
            venueOurs: 0, // full by others…
            ordered: true, // …but ordered anyway
            onTap: () {},
          ),
        ),
      ),
    ));

    final border = borderOf(tester);
    expect(border.top.color, isNot(theme.error));
    final timeText = tester.widget<Text>(find.text('18:00'));
    expect(timeText.style?.decoration, isNot(TextDecoration.lineThrough));
    expect(find.text('0/0'), findsOneWidget); // ordinary numbers, green look
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
