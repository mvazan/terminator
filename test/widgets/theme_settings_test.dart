import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terminator/main.dart';

const _seed = Color(0xFF8E2430);

void main() {
  testWidgets('bez uložené volby jede dnešní chování (systém, běžný kontrast)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: TerminatorApp()));
    await tester.pump();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    final expected = ColorScheme.fromSeed(seedColor: _seed);
    expect(app.theme!.colorScheme.onSurface, expected.onSurface);
    expect(app.theme!.colorScheme.surface, expected.surface);
  });

  testWidgets('volba Tmavý vynutí tmavý jas s maximálním kontrastem',
      (tester) async {
    SharedPreferences.setMockInitialValues({'theme_choice': 'dark'});
    await tester.pumpWidget(const ProviderScope(child: TerminatorApp()));
    await tester.pump(); // prefs se načítají asynchronně
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    final expected = ColorScheme.fromSeed(
        seedColor: _seed, brightness: Brightness.dark, contrastLevel: 1.0);
    expect(app.darkTheme!.colorScheme.onSurface, expected.onSurface);
    expect(app.darkTheme!.colorScheme.surface, expected.surface);
  });
}
