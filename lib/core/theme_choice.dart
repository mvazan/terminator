/// Vzhled appky volený v Nastavení.
library;

import 'package:flutter/material.dart';

/// Tři volby: [system] = dosavadní chování (bordó, světlá/tmavá podle
/// systému), [light]/[dark] vynutí svůj jas — oba s maximálním M3
/// kontrastem, ať je text co nejčitelnější.
enum ThemeChoice { system, light, dark }

/// Persistovaný name → volba; cokoli neznámého padá na [ThemeChoice.system].
ThemeChoice parseThemeChoice(String? name) => ThemeChoice.values
    .firstWhere((c) => c.name == name, orElse: () => ThemeChoice.system);

/// Jak volbu promítnout do MaterialApp: themeMode + contrastLevel pro
/// ColorScheme.fromSeed. Volba "system" drží běžný kontrast — vysoký mají
/// jen explicitní Světlý/Tmavý.
({ThemeMode mode, double contrastLevel}) themePlanFor(ThemeChoice choice) =>
    switch (choice) {
      ThemeChoice.system => (mode: ThemeMode.system, contrastLevel: 0.0),
      ThemeChoice.light => (mode: ThemeMode.light, contrastLevel: 1.0),
      ThemeChoice.dark => (mode: ThemeMode.dark, contrastLevel: 1.0),
    };
