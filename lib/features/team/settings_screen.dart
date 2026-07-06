import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';

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
          for (final kind in NotificationKind.values)
            _NotificationKindTile(
              kind: kind,
              pref: prefs[kind] ?? NotificationPref.fallback(kind),
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

  NotificationKind get kind => widget.kind;
  NotificationPref get pref => widget.pref;

  String _statusLabel() {
    final now = DateTime.now();
    if (!pref.enabled) return 'vypnuto';
    if (pref.isMutedAt(now)) {
      final until = pref.mutedUntil!.toLocal();
      final untilDay = Day.fromDateTime(until);
      final time =
          '${until.hour}:${until.minute.toString().padLeft(2, '0')}';
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
        final hours = await _askCustomHours(context);
        if (hours != null && hours > 0 && context.mounted) {
          await _mute(context, Duration(minutes: (hours * 60).round()));
        }
    }
  }

  Future<void> _mute(BuildContext context, Duration duration) =>
      _save(context,
          enabled: true, mutedUntil: DateTime.now().add(duration));

  // Supabase upserts on this screen usually finish in ~150ms — faster than
  // a spinner is perceptible. Enforce a minimum visible time so the tap
  // always reads as "something happened", instead of looking like a no-op.
  static const _minSpinnerTime = Duration(milliseconds: 350);

  Future<void> _save(BuildContext context,
      {required bool enabled, DateTime? mutedUntil}) async {
    setState(() => _saving = true);
    final started = DateTime.now();
    try {
      await tryAction(
        context,
        () => Api.setNotificationPref(kind,
            enabled: enabled, mutedUntil: mutedUntil),
      );
    } finally {
      final elapsed = DateTime.now().difference(started);
      if (elapsed < _minSpinnerTime) {
        await Future.delayed(_minSpinnerTime - elapsed);
      }
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<double?> _askCustomHours(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ztlumit na kolik hodin?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            hintText: 'např. 24 nebo 0,5',
            suffixText: 'h',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Zrušit')),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              double.tryParse(controller.text.replaceAll(',', '.')),
            ),
            child: const Text('Ztlumit'),
          ),
        ],
      ),
    );
  }
}
