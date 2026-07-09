import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import '../venues/venues_screen.dart';

/// User settings. First section: per-kind notification control —
/// enabled / disabled / muted for 1h, 3h, 6h, 12h, or a custom number of
/// hours. Enforced server-side by the notify Edge Function, so it applies
/// to background pushes too.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(myNotificationPrefsProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('Nastavení')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Upozornění',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Každý druh upozornění můžeš vypnout nebo na chvíli ztlumit. '
              'Ztlumení vyprší samo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          // "Návrhy termínů" is hidden while proposal voting itself is hidden.
          for (final kind in NotificationKind.values)
            if (kind != NotificationKind.proposal)
              _NotificationKindTile(
                kind: kind,
                pref: prefs[kind] ?? NotificationPref.fallback(kind),
              ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Kuželny'),
            subtitle: const Text('Počet drah, adresa, kontakty'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VenuesScreen()),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

const _kindLabels = {
  NotificationKind.newMember: (
    'Nový člen',
    'Někdo se přidal a čeká na schválení',
    Icons.person_add_alt,
  ),
  NotificationKind.newTournament: (
    'Nový turnaj',
    'Někdo založil turnaj',
    Icons.emoji_events_outlined,
  ),
  NotificationKind.proposal: (
    'Návrhy termínů',
    '„Beru čtvrtek — kdo je pro?"',
    Icons.how_to_vote_outlined,
  ),
  NotificationKind.order: (
    'Objednávky',
    'Termín objednán nebo zrušen',
    Icons.receipt_long_outlined,
  ),
  NotificationKind.chat: (
    'Zprávy v chatech',
    'Jednotlivé chaty jde ztlumit i zvlášť',
    Icons.chat_bubble_outline,
  ),
  NotificationKind.threshold: (
    'Dá se objednat',
    'Termín dosáhl minima hráčů',
    Icons.notifications_active_outlined,
  ),
  NotificationKind.newPublicTournament: (
    'Nově vypsané turnaje',
    'Appka hlídá weby s turnaji a dá vědět, když někdo vypíše nový',
    Icons.travel_explore_outlined,
  ),
};

class _NotificationKindTile extends StatefulWidget {
  const _NotificationKindTile({required this.kind, required this.pref});

  final NotificationKind kind;
  final NotificationPref pref;

  @override
  State<_NotificationKindTile> createState() => _NotificationKindTileState();
}

class _NotificationKindTileState extends State<_NotificationKindTile> {
  bool _saving = false;

  // What the user just chose. Shown immediately so the icon reflects the new
  // state right away — the notification_prefs stream that carries the real
  // value back has Realtime latency, and without this the tile would briefly
  // flash the OLD icon after the save finishes, until the stream catches up.
  NotificationPref? _optimistic;

  NotificationKind get kind => widget.kind;

  // Prefer the just-chosen value; fall back to what the stream last delivered.
  NotificationPref get pref => _optimistic ?? widget.pref;

  @override
  void didUpdateWidget(_NotificationKindTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Stream delivered a value matching our optimistic guess → drop the guess
    // and let the stream be the source of truth again.
    if (_optimistic != null && _samePref(widget.pref, _optimistic!)) {
      _optimistic = null;
    }
  }

  bool _samePref(NotificationPref a, NotificationPref b) =>
      a.enabled == b.enabled && a.mutedUntil == b.mutedUntil;

  String _statusLabel() {
    final now = DateTime.now();
    if (!pref.enabled) return 'vypnuto';
    if (pref.isMutedAt(now)) {
      final until = pref.mutedUntil!.toLocal();
      final untilDay = Day.fromDateTime(until);
      final time = HourMinute(until.hour, until.minute).display();
      return untilDay == today()
          ? 'ztlumeno do $time'
          : 'ztlumeno do ${dayLabel(untilDay)} $time';
    }
    return 'zapnuto';
  }

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, icon) = _kindLabels[kind]!;
    final active = pref.isActiveAt(DateTime.now());

    return ListTile(
      leading: Icon(icon,
          color: active ? null : Theme.of(context).disabledColor),
      title: Text(title),
      subtitle: Text('$subtitle · ${_statusLabel()}'),
      trailing: _saving
          ? const SizedBox(
              width: 24,
              height: 24,
              child: Padding(
                padding: EdgeInsets.all(2),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : PopupMenuButton<String>(
              icon: Icon(
                !pref.enabled
                    ? Icons.notifications_off_outlined
                    : (active
                        ? Icons.notifications_active_outlined
                        : Icons.snooze),
              ),
              onSelected: (choice) => _apply(context, choice),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'on', child: Text('Zapnout')),
                PopupMenuItem(
                    value: 'mute1', child: Text('Ztlumit na 1 h')),
                PopupMenuItem(
                    value: 'mute3', child: Text('Ztlumit na 3 h')),
                PopupMenuItem(
                    value: 'mute6', child: Text('Ztlumit na 6 h')),
                PopupMenuItem(
                    value: 'mute12', child: Text('Ztlumit na 12 h')),
                PopupMenuItem(
                    value: 'custom', child: Text('Ztlumit na… (vlastní)')),
                PopupMenuItem(value: 'off', child: Text('Vypnout')),
              ],
            ),
    );
  }

  Future<void> _apply(BuildContext context, String choice) async {
    switch (choice) {
      case 'on':
        await _save(context, enabled: true);
      case 'off':
        await _save(context, enabled: false);
      case 'mute1':
        await _mute(context, const Duration(hours: 1));
      case 'mute3':
        await _mute(context, const Duration(hours: 3));
      case 'mute6':
        await _mute(context, const Duration(hours: 6));
      case 'mute12':
        await _mute(context, const Duration(hours: 12));
      case 'custom':
        final input = await promptText(context,
            title: 'Ztlumit na kolik hodin?',
            hint: 'např. 24 nebo 0,5',
            suffixText: 'h',
            confirmLabel: 'Ztlumit',
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true));
        final hours = double.tryParse((input ?? '').replaceAll(',', '.'));
        if (hours != null && hours > 0 && context.mounted) {
          await _mute(context, Duration(minutes: (hours * 60).round()));
        }
    }
  }

  Future<void> _mute(BuildContext context, Duration duration) =>
      _save(context,
          enabled: true, mutedUntil: DateTime.now().add(duration));

  Future<void> _save(BuildContext context,
      {required bool enabled, DateTime? mutedUntil}) async {
    setState(() => _saving = true);
    var ok = false;
    try {
      await tryAction(
        context,
        () async {
          await Api.setNotificationPref(kind,
              enabled: enabled, mutedUntil: mutedUntil);
          ok = true;
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          // Keep showing the chosen state until the stream confirms it,
          // so the icon never flashes back to the old value.
          if (ok) {
            final chosen = NotificationPref(
                kind: kind, enabled: enabled, mutedUntil: mutedUntil);
            _optimistic =
                _samePref(chosen, widget.pref) ? null : chosen;
          }
        });
      }
    }
  }

}
