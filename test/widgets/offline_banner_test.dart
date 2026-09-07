import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/core/offline_banner.dart';
import 'package:terminator/data/live_refresh.dart';
import 'package:terminator/data/providers.dart';

void main() {
  late StreamController<bool> connected;

  setUp(() => connected = StreamController<bool>.broadcast());
  tearDown(() => connected.close());

  Future<void> pumpBanner(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            realtimeConnectedProvider.overrideWith((ref) => connected.stream),
            currentUserIdProvider.overrideWithValue('me'),
          ],
          child: const MaterialApp(
            home: OfflineBanner(child: Scaffold(body: Text('obsah'))),
          ),
        ),
      );

  final banner = find.textContaining('Offline');

  testWidgets('spadlý socket se hlásí až po chvíli, ne hned', (tester) async {
    await pumpBanner(tester);
    connected.add(false);
    await tester.pump();
    expect(banner, findsNothing, reason: 'krátký výpadek se nehlásí');

    await tester.pump(const Duration(seconds: 4));
    expect(banner, findsOneWidget);

    connected.add(true);
    await tester.pump(); // doručení eventu
    await tester.pump(); // překreslení
    expect(banner, findsNothing);
  });

  testWidgets('probuzení appky banner schová — v pozadí je odpojený socket '
      'normální stav', (tester) async {
    await pumpBanner(tester);
    connected.add(false);
    await tester.pump(const Duration(seconds: 4));
    expect(banner, findsOneWidget);

    LiveRefresh.request();
    await tester.pump();
    await tester.pump();
    expect(banner, findsNothing, reason: 'nejdřív dej spojení šanci');

    // Socket se vrátil dřív, než doběhla lhůta po probuzení.
    connected.add(true);
    await tester.pump(const Duration(seconds: 10));
    expect(banner, findsNothing);
  });

  testWidgets('když se spojení po probuzení nevrátí, banner se zase objeví',
      (tester) async {
    await pumpBanner(tester);
    connected.add(false);
    await tester.pump(const Duration(seconds: 4));
    LiveRefresh.request();
    await tester.pump();
    await tester.pump();
    expect(banner, findsNothing);

    await tester.pump(const Duration(seconds: 7));
    expect(banner, findsOneWidget);
  });
}
