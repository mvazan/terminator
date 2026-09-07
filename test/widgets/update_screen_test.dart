import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/features/auth/update_screen.dart';

void main() {
  testWidgets('explains the block and offers Google Play', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UpdateScreen()));

    expect(find.text('Je potřeba aktualizace'), findsOneWidget);
    expect(find.textContaining('novější server'), findsOneWidget);
    // FilledButton.icon builds a private subclass, so match by supertype.
    expect(find.text('Otevřít Google Play'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is FilledButton), findsOneWidget);
    expect(find.byIcon(Icons.system_update), findsNWidgets(2));
  });
}
