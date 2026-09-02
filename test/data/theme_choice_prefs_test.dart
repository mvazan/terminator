import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terminator/core/theme_choice.dart';
import 'package:terminator/data/local_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uložená volba se načte při startu', () async {
    SharedPreferences.setMockInitialValues({'theme_choice': 'dark'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(themeChoiceProvider), ThemeChoice.system); // default
    await Future<void>.delayed(Duration.zero); // async _load doběhne
    expect(container.read(themeChoiceProvider), ThemeChoice.dark);
  });

  test('set přepne stav a persistuje name', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(themeChoiceProvider.notifier).set(ThemeChoice.light);
    expect(container.read(themeChoiceProvider), ThemeChoice.light);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_choice'), 'light');
  });
}
