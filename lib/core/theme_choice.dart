/// Vzhled appky volený v Nastavení.
library;

import 'package:flutter/material.dart';

/// Pět voleb ve dvou skupinách. Původní vzhled appky: [system] podle
/// telefonu, [terminatorLight]/[terminatorDark] tytéž barvy, jen s pevně
/// zvoleným jasem bez ohledu na systém. Druhá skupina — [light]/[dark] —
/// jede stejné bordó s maximálním M3 kontrastem, ať je text co
/// nejčitelnější.
///
/// Názvy hodnot jsou perzistované (SharedPreferences) — nepřejmenovávat,
/// jinak uložená volba po updatu spadne zpátky na [system].
enum ThemeChoice { system, terminatorLight, terminatorDark, light, dark }

/// Persistovaný name → volba; cokoli neznámého padá na [ThemeChoice.system].
ThemeChoice parseThemeChoice(String? name) => ThemeChoice.values
    .firstWhere((c) => c.name == name, orElse: () => ThemeChoice.system);

/// Jak volbu promítnout do MaterialApp: themeMode + contrastLevel pro
/// ColorScheme.fromSeed. Vysoký kontrast mají jen volby Světlý/Tmavý;
/// Termínátor v jakékoli podobě drží běžný kontrast, tedy původní barvy.
({ThemeMode mode, double contrastLevel}) themePlanFor(ThemeChoice choice) =>
    switch (choice) {
      ThemeChoice.system => (mode: ThemeMode.system, contrastLevel: 0.0),
      ThemeChoice.terminatorLight => (
          mode: ThemeMode.light,
          contrastLevel: 0.0
        ),
      ThemeChoice.terminatorDark => (
          mode: ThemeMode.dark,
          contrastLevel: 0.0
        ),
      ThemeChoice.light => (mode: ThemeMode.light, contrastLevel: 1.0),
      ThemeChoice.dark => (mode: ThemeMode.dark, contrastLevel: 1.0),
    };
