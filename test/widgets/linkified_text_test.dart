import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/core/ui.dart';

void main() {
  TextSpan rootSpan(WidgetTester tester) =>
      tester.widget<SelectableText>(find.byType(SelectableText)).textSpan!;

  testWidgets('URL becomes an underlined tappable span, text stays intact',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: LinkifiedText('Propozice: https://example.com/prop.pdf, dorazte.'),
      ),
    ));

    final children = rootSpan(tester).children!;
    expect(children, hasLength(3));
    expect((children[0] as TextSpan).text, 'Propozice: ');
    final link = children[1] as TextSpan;
    // Trailing comma belongs to the sentence, not the URL.
    expect(link.text, 'https://example.com/prop.pdf');
    expect(link.style?.decoration, TextDecoration.underline);
    expect(link.recognizer, isNotNull);
    expect((children[2] as TextSpan).text, ', dorazte.');
  });

  testWidgets('text without URLs renders as a single plain span',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: LinkifiedText('Jen text bez odkazu.')),
    ));
    final children = rootSpan(tester).children!;
    expect(children, hasLength(1));
    expect((children.single as TextSpan).recognizer, isNull);
  });
}
