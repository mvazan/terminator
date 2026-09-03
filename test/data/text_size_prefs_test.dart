import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terminator/core/text_size.dart';
import 'package:terminator/data/local_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uložená velikost písma se načte při startu', () async {
    SharedPreferences.setMockInitialValues({'text_size': 'large'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(textSizeProvider), TextSizeChoice.normal);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(textSizeProvider), TextSizeChoice.large);
  });

  test('set přepne stav a persistuje name', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(textSizeProvider.notifier).set(TextSizeChoice.largest);
    expect(container.read(textSizeProvider), TextSizeChoice.largest);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('text_size'), 'largest');
  });
}
