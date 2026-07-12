import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/data/providers.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/features/tournaments/tournaments_screen.dart';

import '../domain/helpers.dart';

void main() {
  // Two future tournaments at different venues; "b" is hidden by me.
  final aaa = makeTournament(
    id: 'a',
    name: 'Cena Vracova',
    venueId: 'v1',
    startsOn: Day(2030, 4, 24),
    endsOn: Day(2030, 4, 26),
  );
  final bbb = makeTournament(
    id: 'b',
    name: 'Memoriál',
    venueId: 'v2',
    startsOn: Day(2030, 5, 1),
    endsOn: Day(2030, 5, 3),
  );

  Widget wrap({Set<String> myHidden = const {}}) => ProviderScope(
        overrides: [
          allTournamentsProvider
              .overrideWithValue(AsyncValue.data([aaa, bbb])),
          tournamentsProvider.overrideWithValue(AsyncValue.data([aaa])),
          myHiddenTournamentsProvider
              .overrideWithValue(AsyncValue.data(myHidden)),
          venueNamesProvider
              .overrideWithValue({'v1': 'Vracov', 'v2': 'Olomouc'}),
          slotsProvider.overrideWithValue(const AsyncValue.data([])),
          availabilityProvider.overrideWithValue(const AsyncValue.data([])),
          // Derives from currentUserId (Supabase) — pin it in tests.
          tournamentInterestProvider.overrideWithValue(const {}),
        ],
        child: const MaterialApp(home: TournamentsScreen()),
      );

  testWidgets('venue leads the tile; tournament name is the subtitle',
      (tester) async {
    await tester.pumpWidget(wrap());

    // Title = "Venue (kind)", subtitle starts with the tournament name.
    expect(find.text('Vracov (dvojice)'), findsOneWidget);
    expect(find.textContaining('Cena Vracova ·'), findsOneWidget);
  });

  testWidgets(
      'eye mode reveals hidden (dimmed, sorted last); checkbox edits stay '
      'local until commit', (tester) async {
    await tester.pumpWidget(wrap(myHidden: {'b'}));

    // Eye off: hidden tournament invisible.
    expect(find.text('Olomouc (dvojice)'), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();

    // Hidden shown, dimmed, after the visible one.
    expect(find.text('Olomouc (dvojice)'), findsOneWidget);
    expect(find.byType(Opacity), findsOneWidget);
    final yVisible = tester.getTopLeft(find.text('Vracov (dvojice)')).dy;
    final yHidden = tester.getTopLeft(find.text('Olomouc (dvojice)')).dy;
    expect(yHidden, greaterThan(yVisible));

    // Un-hiding via checkbox is purely local (no Supabase in this test —
    // an API call would throw): tile un-dims and re-sorts immediately.
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(find.byType(Opacity), findsNothing);

    // Toggle back so the pending diff is empty when the widget disposes
    // (dispose would otherwise fire the batch API).
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(find.byType(Opacity), findsOneWidget);
  });
}
