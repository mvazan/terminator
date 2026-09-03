import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/core/text_size.dart';

void main() {
  test('kroky kopírují systémové stupně Androidu (100 / 115 / 130 %)', () {
    expect(textSizeFactor(TextSizeChoice.normal), 1.0);
    expect(textSizeFactor(TextSizeChoice.large), 1.15);
    expect(textSizeFactor(TextSizeChoice.largest), 1.3);
  });

  test('parse: round-trip přes name, neznámé/null padá na normal', () {
    for (final c in TextSizeChoice.values) {
      expect(parseTextSizeChoice(c.name), c);
    }
    expect(parseTextSizeChoice(null), TextSizeChoice.normal);
    expect(parseTextSizeChoice('mega'), TextSizeChoice.normal);
  });

  group('AppTextScaler', () {
    test('normal nechá systémové měřítko být', () {
      final s = AppTextScaler(TextScaler.linear(1.3), TextSizeChoice.normal);
      expect(s.scale(16), closeTo(20.8, 0.01));
    });

    test('volba se násobí na systémové měřítko', () {
      expect(
          AppTextScaler(TextScaler.noScaling, TextSizeChoice.large).scale(16),
          closeTo(18.4, 0.01));
      expect(
          AppTextScaler(TextScaler.noScaling, TextSizeChoice.largest).scale(16),
          closeTo(20.8, 0.01));
      // Systém 130 % + volba "největší" = 169 %.
      expect(
          AppTextScaler(TextScaler.linear(1.3), TextSizeChoice.largest)
              .scale(16),
          closeTo(27.04, 0.01));
    });

    test('nikdy víc než 200 % návrhové velikosti (WCAG 1.4.4)', () {
      // Systém už na maximu Androidu 14 (200 %) — volba to nesmí přestřelit.
      final s = AppTextScaler(TextScaler.linear(2.0), TextSizeChoice.largest);
      expect(s.scale(16), 32.0);
      expect(s.scale(20), 40.0);
    });

    test('nulová velikost zůstane nulová', () {
      expect(
          AppTextScaler(TextScaler.noScaling, TextSizeChoice.largest).scale(0),
          0.0);
    });
  });
}
