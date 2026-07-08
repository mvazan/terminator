/// On-device UI preferences that persist across app restarts but have
/// nothing to do with the team (unlike notification_prefs in Supabase).
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _showWhoIsInKey = 'show_who_is_in';
const _chatReadsKey = 'chat_reads';

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

/// When each chat was last read on this device, keyed like chat_mutes:
/// "tournamentId|day" ('' day = tournament chat). Unread counts and the
/// chat-list ordering derive from comparing these with the message stream.
/// Device-local on purpose — no backend table, a reinstall just resets it.
final chatReadsProvider =
    NotifierProvider<ChatReadsNotifier, Map<String, DateTime>>(
        ChatReadsNotifier.new);

class ChatReadsNotifier extends Notifier<Map<String, DateTime>> {
  @override
  Map<String, DateTime> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_chatReadsKey);
    if (raw == null) return;
    state = {
      for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
        e.key: DateTime.parse(e.value as String),
    };
  }

  Future<void> markRead(String chatKey, DateTime at) async {
    final current = state[chatKey];
    if (current != null && !at.isAfter(current)) return;
    state = {...state, chatKey: at};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _chatReadsKey,
        jsonEncode({
          for (final e in state.entries) e.key: e.value.toIso8601String(),
        }));
  }
}
