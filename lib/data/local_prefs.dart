/// On-device UI preferences that persist across app restarts but have
/// nothing to do with the team (unlike notification_prefs in Supabase).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _showWhoIsInKey = 'show_who_is_in';

/// Whether the "who's in" name list is shown under every slot in the
/// tournament heatmap (vs. just the count). Toggled from the tournament
/// detail app bar menu; remembered across app restarts.
final showWhoIsInProvider =
    NotifierProvider<ShowWhoIsInNotifier, bool>(ShowWhoIsInNotifier.new);

class ShowWhoIsInNotifier extends Notifier<bool> {
  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_showWhoIsInKey) ?? false;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showWhoIsInKey, state);
  }
}
