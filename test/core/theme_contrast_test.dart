import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/core/app_theme.dart';

import 'contrast.dart';

/// WCAG 2.1 AA: běžný text 4.5:1, tvary a prvky UI 3:1.
const _textAA = 4.5;
const _shapeAA = 3.0;

/// Všechny motivy, které si člověk může v Nastavení zvolit.
const _variants = <(String, Brightness, double)>[
  ('Termínátor světlý', Brightness.light, 0.0),
  ('Termínátor tmavý', Brightness.dark, 0.0),
  ('Světlý (vysoký kontrast)', Brightness.light, 1.0),
  ('Tmavý (vysoký kontrast)', Brightness.dark, 1.0),
];

void expectText(double ratio, String what, String variant) {
  expect(ratio, greaterThanOrEqualTo(_textAA),
      reason: '$variant: $what má kontrast '
          '${ratio.toStringAsFixed(2)}:1, AA chce $_textAA:1');
}

void main() {
  for (final (variant, brightness, contrastLevel) in _variants) {
    final theme = appTheme(brightness, contrastLevel);
    final s = theme.colorScheme;
    final page = theme.scaffoldBackgroundColor;

    group(variant, () {
      test('text na kartě i ve vstupním poli je čitelný', () {
        final card = theme.cardTheme.color!;
        expectText(contrastRatio(theme.textTheme.bodyMedium!.color!, card),
            'text karty', variant);
        expectText(contrastRatio(s.onSurfaceVariant, card),
            'druhotný text karty', variant);
        expectText(
            contrastRatio(theme.textTheme.bodyMedium!.color!,
                theme.inputDecorationTheme.fillColor!),
            'text ve vstupním poli',
            variant);
      });

      test('karta je vidět proti pozadí stránky', () {
        final side = (theme.cardTheme.shape! as RoundedRectangleBorder).side;
        final visible = [
          contrastRatio(theme.cardTheme.color!, page),
          if (side.style != BorderStyle.none) contrastRatio(side.color, page),
        ].reduce((a, b) => a > b ? a : b);
        expect(visible, greaterThanOrEqualTo(_shapeAA),
            reason: '$variant: karta splývá s pozadím — výplň i obrys pod '
                '$_shapeAA:1 (nejlepší ${visible.toStringAsFixed(2)}:1)');
      });

      for (final mine in [true, false]) {
        final who = mine ? 'moje' : 'cizí';
        final b = bubbleColors(s, mine: mine);

        test('$who bublina: text, čas, citace i reakce jsou čitelné', () {
          expectText(contrastRatio(b.on, b.fill), '$who bublina — text',
              variant);
          expectText(
              contrastRatio(composite(b.subtle, b.fill), b.fill),
              '$who bublina — čas',
              variant);
          final nested = composite(b.nested, b.fill);
          expectText(contrastRatio(b.on, nested),
              '$who bublina — text citace', variant);
          expectText(contrastRatio(b.on, nested),
              '$who bublina — text reakce', variant);
        });

        test('$who bublina je vidět proti pozadí stránky', () {
          final visible = [
            contrastRatio(b.fill, page),
            contrastRatio(b.border, page),
          ].reduce((a, b) => a > b ? a : b);
          expect(visible, greaterThanOrEqualTo(_shapeAA),
              reason: '$variant: $who bublina splývá s pozadím — výplň i '
                  'obrys pod $_shapeAA:1 '
                  '(nejlepší ${visible.toStringAsFixed(2)}:1)');
        });
      }

      test('neodeslaná bublina: chybový stav je čitelný', () {
        final failed = bubbleColors(s, mine: true, failed: true);
        expectText(contrastRatio(failed.on, failed.fill),
            'neodeslaná bublina — text', variant);
      });
    });
  }
}
