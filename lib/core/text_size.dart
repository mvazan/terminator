/// Velikost písma volená v Nastavení.
///
/// Appka respektuje systémové měřítko Androidu (Flutter to dělá sám); tohle
/// je násobek NAVÍC, pro lidi, kterým vyhovuje větší písmo jen tady.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Tři stupně. Násobky kopírují systémové stupně Androidu (velké 115 %,
/// největší 130 %), ať je výsledek pro oko povědomý.
enum TextSizeChoice { normal, large, largest }

double textSizeFactor(TextSizeChoice choice) => switch (choice) {
      TextSizeChoice.normal => 1.0,
      TextSizeChoice.large => 1.15,
      TextSizeChoice.largest => 1.3,
    };

/// Persistovaný name → volba; cokoli neznámého padá na normální velikost.
TextSizeChoice parseTextSizeChoice(String? name) => TextSizeChoice.values
    .firstWhere((c) => c.name == name, orElse: () => TextSizeChoice.normal);

/// Systémové měřítko vynásobené volbou z Nastavení, se stropem na
/// dvojnásobku návrhové velikosti: WCAG 1.4.4 chce, aby text šel zvětšit
/// na 200 %, a tam má strop i Android 14. Bez stropu by se systémové
/// maximum a volba "největší" vynásobily na 260 % a rozbily rozvržení.
class AppTextScaler extends TextScaler {
  const AppTextScaler(this.system, this.choice);

  /// Měřítko z nastavení telefonu.
  final TextScaler system;
  final TextSizeChoice choice;

  static const _maxOfDesignSize = 2.0;

  @override
  double scale(double fontSize) => math.min(
      system.scale(fontSize) * textSizeFactor(choice),
      fontSize * _maxOfDesignSize);

  @override
  double get textScaleFactor => scale(14) / 14;
}
