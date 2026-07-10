import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/data/providers.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/features/tournaments/timeline_screen.dart';

import '../domain/helpers.dart';

void main() {
  testWidgets('season calendar draws a visible, day-proportional bar',
      (tester) async {
    // 24.–26. 4. 2026 is Fri–Sun: one week column, bar = right 3/7 of it.
    final t = makeTournament(
      startsOn: Day(2026, 4, 24),
      endsOn: Day(2026, 4, 26),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tournamentsProvider.overrideWithValue(AsyncValue.data([t])),
          venueNamesProvider.overrideWithValue({'v1': 'Vracov'}),
        ],
        child: const MaterialApp(home: TimelineScreen()),
      ),
    );

    // The bar is the ColoredBox inside the week cell. It must actually have
    // size — a zero-height box was the regression this test guards against.
    // (MaterialApp adds its own transparent ColoredBox — match by bar color.)
    final bar = find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color.a == 1.0);
    expect(bar, findsOneWidget);
    final size = tester.getSize(bar);
    expect(size.height, greaterThan(20)); // fills the cell vertically
    // 3/7 of the 84 px cell (fractions of the inner width, border-adjusted).
    expect(size.width, closeTo(84 * 3 / 7, 2.0));
  });
}
