import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/core/theme_choice.dart';

void main() {
  test('volba Termínátor = dnešní chování: podle systému, běžný kontrast', () {
    final plan = themePlanFor(ThemeChoice.system);
    expect(plan.mode, ThemeMode.system);
    expect(plan.contrastLevel, 0.0);
  });

  test('Světlý a Tmavý vynutí svůj jas s maximálním kontrastem', () {
    final light = themePlanFor(ThemeChoice.light);
    expect(light.mode, ThemeMode.light);
    expect(light.contrastLevel, 1.0);

    final dark = themePlanFor(ThemeChoice.dark);
    expect(dark.mode, ThemeMode.dark);
    expect(dark.contrastLevel, 1.0);
  });

  test('parse: round-trip přes name, neznámé/null padá na system', () {
    for (final c in ThemeChoice.values) {
      expect(parseThemeChoice(c.name), c);
    }
    expect(parseThemeChoice(null), ThemeChoice.system);
    expect(parseThemeChoice('neon'), ThemeChoice.system);
  });
}
