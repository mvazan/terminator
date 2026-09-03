/// WCAG kontrastní poměry — počítá s nimi volba čitelnější barvy textu
/// v app_theme i test kontrastu.
library;

import 'dart:math' as math;
import 'dart:ui';

/// Relativní jas podle WCAG 2.1 (sRGB, gamma-korigovaný).
double relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// Kontrastní poměr dvou NEPRŮHLEDNÝCH barev: 1.0 (stejné) až 21.0
/// (černá/bílá). AA chce 4.5 pro běžný text, 3.0 pro velký text a prvky UI.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

/// [fg] s vlastní alfou složená přes neprůhledné [bg] — tak, jak to
/// vykreslí Flutter. Poloprůhledné pozadí je nutné složit dřív, než se
/// kontrast vůbec dá měřit.
Color composite(Color fg, Color bg) {
  final a = fg.a;
  return Color.from(
    alpha: 1.0,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}
