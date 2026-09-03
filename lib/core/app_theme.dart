/// Vzhled appky na jednom místě — ať jde měřit kontrast v testech
/// (test/core/theme_contrast_test.dart) a ne jen odhadovat od oka.
library;

import 'package:flutter/material.dart';

import 'contrast.dart';

/// Kuželky bordó — identita appky, ze které se odvozuje celé schéma.
const seedColor = Color(0xFF8E2430);

/// Ta z [a]/[b], která je na výplni [fill] čitelnější.
Color _readableOn(Color fill, Color a, Color b) =>
    contrastRatio(a, fill) >= contrastRatio(b, fill) ? a : b;

/// Barvy jedné barevné plochy (bublina, zvýrazněná karta, buňka mřížky) —
/// jediné místo, odkud je bere widget i test kontrastu
/// (test/core/theme_contrast_test.dart). Výplň bez svojí `on` barvy je
/// past: v motivech s vysokým kontrastem ztmavne a text na ní zmizí.
class SurfaceColors {
  const SurfaceColors({
    required this.fill,
    required this.on,
    required this.border,
  });

  /// Pozadí bubliny.
  final Color fill;

  /// Text a ikony na bublině.
  final Color on;

  /// Obrys — aby byl tvar vidět i tam, kde je výplň skoro jako pozadí.
  final Color border;

  /// Vnořené plochy uvnitř bubliny (citace, žetony reakcí).
  Color get nested => on.withValues(alpha: 0.12);

  /// Druhotný text na bublině (čas).
  Color get subtle => on.withValues(alpha: 0.75);
}

/// Barvy bubliny: text VŽDY patří k výplni (onPrimaryContainer na mojí,
/// onSurface na cizí) — jinak se v motivech s vysokým kontrastem, kde je
/// primaryContainer sytě bordó, propadne až k 1.8:1. Obrys z [outline]
/// dělá tvar viditelný i tam, kde je výplň skoro jako pozadí stránky.
SurfaceColors bubbleColors(ColorScheme s,
    {required bool mine, bool failed = false}) {
  if (failed) {
    return SurfaceColors(
      fill: s.errorContainer,
      on: s.onErrorContainer,
      border: s.error,
    );
  }
  return SurfaceColors(
    fill: mine ? s.primaryContainer : s.surfaceContainerHigh,
    on: mine ? s.onPrimaryContainer : s.onSurface,
    border: s.outline,
  );
}

/// Zvýrazněná karta (nejbližší start na Moje starty) — bordó výplň, text
/// k ní patřící.
SurfaceColors highlightSurface(ColorScheme s) => SurfaceColors(
      fill: s.primaryContainer,
      on: s.onPrimaryContainer,
      border: s.outline,
    );

/// Buňka mřížky zájmu: výplň přechází podle [intensity] (0 = nikdo,
/// 1 = plný zájem) z neutrální plochy do bordó. Barva textu se v půli
/// přechodu překlápí — pevná volba by na druhém konci spadla až k 1.8:1,
/// tenhle výběr drží nejhorší případ na 5.6:1.
SurfaceColors gridCellSurface(ColorScheme s, double intensity) {
  final fill =
      Color.lerp(s.surfaceContainerHighest, s.primaryContainer, intensity)!;
  return SurfaceColors(
    fill: fill,
    on: _readableOn(fill, s.onSurface, s.onPrimaryContainer),
    border: s.outlineVariant,
  );
}

/// Motiv pro daný jas; [contrastLevel] 0 = běžný, 1 = maximální kontrast
/// (volby Světlý/Tmavý v Nastavení).
ThemeData appTheme(Brightness brightness, double contrastLevel) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
    contrastLevel: contrastLevel,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surfaceContainerLowest,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainerLowest,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainer,
      // Obrys, ne stín: výplň karty se od pozadí liší jen o 1.2:1 (sousední
      // tóny palety), takže bez něj karta na stránce splývá.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outline),
      ),
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: scheme.surfaceContainer,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      indicatorColor: scheme.primaryContainer,
      // Ikona vybrané záložky leží na pilulce (primaryContainer), popisek
      // pod ní na pozadí lišty — každý potřebuje svou `on` barvu.
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          )),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: DividerThemeData(
      // Plná síla: se 40% alfou byla čára prakticky neviditelná.
      color: scheme.outlineVariant,
    ),
  );
}
