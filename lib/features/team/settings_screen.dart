import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';
import '../../core/text_size.dart';
import '../../core/theme_choice.dart';
import '../../core/ui.dart';
import '../../data/local_prefs.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import '../venues/venues_screen.dart';

/// The Play review demo account is shared, so linking "your" Google calendar
/// to it makes no sense — the calendar section stays hidden for it.
bool get _isDemoAccount =>
    Supabase.instance.client.auth.currentUser?.email?.toLowerCase() ==
    AppConfig.demoEmail.toLowerCase();

/// Řádek "název · aktuální volba" otevírající dialog s rádii. Používají ho
/// obě nastavení zobrazení (vzhled, velikost písma) — jen toto zařízení.
class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.labels,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(labels[value]!),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showDialog<void>(
        context: context,
        builder: (dialogCtx) => SimpleDialog(
          title: Text(title),
          children: [
            RadioGroup<T>(
              groupValue: value,
              onChanged: (v) {
                Navigator.pop(dialogCtx);
                if (v != null) onChanged(v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in labels.entries)
                    RadioListTile<T>(
                      value: entry.key,
                      title: Text(entry.value),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Volba vzhledu: Termínátor = bordó podle systému, Světlý/Tmavý vynutí
/// jas s maximálním kontrastem kvůli čitelnosti.
class _ThemeTile extends ConsumerWidget {
  const _ThemeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _ChoiceTile(
        icon: Icons.palette_outlined,
        title: 'Vzhled',
        value: ref.watch(themeChoiceProvider),
        labels: const {
          ThemeChoice.system: 'Termínátor — podle systému',
          ThemeChoice.light: 'Světlý — vysoký kontrast',
          ThemeChoice.dark: 'Tmavý — vysoký kontrast',
        },
        onChanged: (v) => ref.read(themeChoiceProvider.notifier).set(v),
      );
}

/// Velikost písma NAD rámec systémového nastavení telefonu.
class _TextSizeTile extends ConsumerWidget {
  const _TextSizeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _ChoiceTile(
        icon: Icons.format_size,
        title: 'Velikost písma',
        value: ref.watch(textSizeProvider),
        labels: const {
          TextSizeChoice.normal: 'Normální — jako v telefonu',
          TextSizeChoice.large: 'Větší (115 %)',
          TextSizeChoice.largest: 'Největší (130 %)',
        },
        onChanged: (v) => ref.read(textSizeProvider.notifier).set(v),
      );
}

/// User settings. First section: per-kind notification control —
/// enabled / disabled / muted for 1h, 3h, 6h, 12h, or a custom number of
/// hours. Enforced server-side by the notify Edge Function, so it applies
/// to background pushes too.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(myNotificationPrefsProvider).value ?? const {};
    final me = ref.watch(myProfileProvider).value;
    final superadmin = me?.superadmin ?? false;
    final team = ref.watch(myTeamProvider);
    final isFounder =
        me != null && team != null && team.createdBy == me.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Nastavení')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Zobrazení',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const _ThemeTile(),
          const _TextSizeTile(),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
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
          // "Návrhy termínů" is hidden while proposal voting itself is
          // hidden; "Nový tým" only ever reaches the superadmin.
          for (final kind in NotificationKind.values)
            if (kind != NotificationKind.proposal &&
                (kind != NotificationKind.newTeam || superadmin))
              _NotificationKindTile(
                kind: kind,
                pref: prefs[kind] ?? NotificationPref.fallback(kind),
              ),
          // Hidden without a Google client ID baked in, and for the Play
          // review demo account (a shared account has no calendar to link).
          if (AppConfig.hasGoogleCalendar && !_isDemoAccount) ...[
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Kalendář',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const _CalendarLinkTile(),
          ],
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
          // Founder-only: how the (deliberately obscure) manage mode works.
          if (isFounder) ...[
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Režim správy — jen pro zakladatele',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Podrž 3 sekundy prst na nadpisu „Turnaje" nebo „Tým" a '
                'zadej PIN. Odemkne se skrývání turnajů pro celý tým a '
                'skrývání členů (např. když někdo z party odejde). Zamkneš '
                'stejným podržením.\n\n'
                'PIN správy: ${team.managePin}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Google Calendar link: connect (opens Google's consent page in the
/// browser), show the current state, or disconnect. Nothing comes back into
/// the app via a deep link — the backend writes the result and this tile
/// flips on its own through the live stream.
class _CalendarLinkTile extends ConsumerStatefulWidget {
  const _CalendarLinkTile();

  @override
  ConsumerState<_CalendarLinkTile> createState() => _CalendarLinkTileState();
}

class _CalendarLinkTileState extends ConsumerState<_CalendarLinkTile> {
  bool _busy = false;

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      final url = await Api.calendarConsentUrl();
      if (!mounted) return;
      launchWeb(url.toString());
      snack(context, 'Dokonči propojení v prohlížeči a vrať se sem.');
    } catch (e) {
      if (mounted) snack(context, 'Propojení se nepovedlo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await confirmDialog(
      context,
      title: 'Odpojit kalendář?',
      message: 'Kalendář „Termínátor" se z Googlu smaže i se starty — po '
          'odpojení už na něj appka nedosáhne, nechat ho by znamenalo '
          'hromadit mrtvé kopie. Propojit se můžeš kdykoli znovu, starty '
          'i připomínky se vrátí.',
      confirmLabel: 'Odpojit a smazat',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      // Čeká se schválně: dokud odpojení nedoběhne, tile nesmí nabídnout
      // nové propojení — jinak by po sobě zůstal osiřelý kalendář.
      final orphaned = await Api.disconnectCalendar();
      if (mounted) {
        snack(
          context,
          orphaned
              ? 'Odpojeno. Přístup byl odvolaný už dřív, takže kalendář '
                  '„Termínátor" v Googlu zůstal — smaž si ho tam sám(a).'
              : 'Kalendář odpojen a smazán.',
        );
      }
    } catch (e) {
      if (mounted) {
        snack(context, 'Odpojení se nepovedlo, nic se nezměnilo. '
            'Zkus to prosím znovu.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reminder editor: a live list of "N minut/hodin/dní předem" entries with
  /// add/remove, mirroring Google Calendar's own model (max 5, max 4 weeks).
  /// Every change is saved immediately — the sheet watches the same stream
  /// as the tile, so it redraws itself when the row lands.
  Future<void> _editReminders() {
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final link =
              ref.watch(myCalendarLinkProvider).value ?? CalendarLink.none;
          final minutes = link.reminderMinutes;
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Připomínky startů v kalendáři'),
                ),
                if (minutes.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.notifications_off_outlined),
                    title: Text('Žádné připomínky'),
                    subtitle: Text('Starty se přidávají tiše, bez upozornění.'),
                  ),
                for (final m in minutes)
                  ListTile(
                    leading: const Icon(Icons.notifications_none_outlined),
                    title: Text(reminderOffsetLabel(m)),
                    trailing: IconButton(
                      tooltip: 'Odebrat',
                      icon: const Icon(Icons.close),
                      onPressed: () => tryAction(
                          context,
                          () => Api.setCalendarReminders(
                              [for (final x in minutes) if (x != m) x])),
                    ),
                  ),
                if (minutes.length < maxCalendarReminders)
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Přidat připomínku'),
                    onTap: () => _addReminder(context, minutes),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  /// "Number + unit" dialog; converts to minutes and saves.
  Future<void> _addReminder(BuildContext context, List<int> current) async {
    final controller = TextEditingController();
    var unit = _ReminderUnit.hours;
    try {
      final minutes = await showDialog<int>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setState) => AlertDialog(
            title: const Text('Připomínka předem'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Kolik'),
                ),
                const SizedBox(height: 12),
                SegmentedButton<_ReminderUnit>(
                  segments: [
                    for (final u in _ReminderUnit.values)
                      ButtonSegment(value: u, label: Text(u.label)),
                  ],
                  selected: {unit},
                  onSelectionChanged: (s) => setState(() => unit = s.first),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Zrušit')),
              FilledButton(
                onPressed: () {
                  final n = int.tryParse(controller.text.trim());
                  if (n == null || n <= 0) return;
                  Navigator.pop(dialogContext, n * unit.inMinutes);
                },
                child: const Text('Přidat'),
              ),
            ],
          ),
        ),
      );
      if (minutes == null || !context.mounted) return;
      if (minutes > maxReminderMinutes) {
        snack(context, 'Nejdál to jde 4 týdny (28 dní) předem.');
        return;
      }
      await tryAction(
          context, () => Api.setCalendarReminders([...current, minutes]));
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(myCalendarLinkProvider).value ?? CalendarLink.none;

    return switch (link.status) {
      CalendarLinkStatus.linked => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('Google kalendář'),
              subtitle: Text(link.googleEmail == null
                  ? 'Propojeno — starty se přidávají samy.'
                  : 'Propojeno jako ${link.googleEmail}.'),
              trailing: _busy
                  ? const _TileSpinner()
                  : TextButton(
                      onPressed: _disconnect, child: const Text('Odpojit')),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_none_outlined),
              title: const Text('Připomínky startů'),
              subtitle: Text(remindersSummary(link.reminderMinutes)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _editReminders,
            ),
          ],
        ),
      CalendarLinkStatus.pending => ListTile(
          leading: const Icon(Icons.event_outlined),
          title: const Text('Google kalendář'),
          subtitle: Text(link.lastError ?? 'Propojuje se…'),
          trailing: _busy
              ? const _TileSpinner()
              : TextButton(
                  onPressed: _connect, child: const Text('Zkusit znovu')),
        ),
      CalendarLinkStatus.broken => ListTile(
          leading: Icon(Icons.event_busy_outlined,
              color: Theme.of(context).colorScheme.error),
          title: const Text('Google kalendář'),
          subtitle: Text(link.lastError == null
              ? 'Propojení se přerušilo.'
              : '${link.lastError} Propoj ho prosím znovu.'),
          trailing: _busy
              ? const _TileSpinner()
              : TextButton(onPressed: _connect, child: const Text('Propojit')),
        ),
      CalendarLinkStatus.notLinked => ListTile(
          leading: const Icon(Icons.event_outlined),
          title: const Text('Propojit Google kalendář'),
          subtitle: const Text(
              'Tvoje starty se budou samy přidávat do kalendáře „Termínátor" '
              've tvém Google účtu — a mizet, když se objednávka zruší.'),
          isThreeLine: true,
          trailing: _busy ? const _TileSpinner() : null,
          onTap: _busy ? null : _connect,
        ),
    };
  }
}

/// Units for the "reminder ahead" dialog, converted to minutes on save.
/// Deliberately no minutes — for a bowling start nobody sets "37 minut
/// předem", and two units keep the dialog one glance wide.
enum _ReminderUnit {
  hours('hodiny', 60),
  days('dny', 1440);

  const _ReminderUnit(this.label, this.inMinutes);

  final String label;
  final int inMinutes;
}

class _TileSpinner extends StatelessWidget {
  const _TileSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
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
  NotificationKind.newTeam: (
    'Nový tým',
    'Někdo založil tým a čeká na schválení (jen správce aplikace)',
    Icons.group_add_outlined,
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
      a.enabled == b.enabled &&
      a.silent == b.silent &&
      a.mutedUntil == b.mutedUntil;

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
    return pref.silent ? 'tiše' : 'zapnuto';
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
                    : (!active
                        ? Icons.snooze
                        : (pref.silent
                            ? Icons.notifications_paused_outlined
                            : Icons.notifications_active_outlined)),
              ),
              onSelected: (choice) => _apply(context, choice),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'on', child: Text('Zapnout (se zvukem)')),
                PopupMenuItem(
                    value: 'silent',
                    child: Text('Jen tiše (bez zvuku, jen lišta)')),
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
      case 'silent':
        await _save(context, enabled: true, silent: true);
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
          enabled: true,
          silent: pref.silent, // muting keeps the chosen delivery level
          mutedUntil: DateTime.now().add(duration));

  Future<void> _save(BuildContext context,
      {required bool enabled,
      bool silent = false,
      DateTime? mutedUntil}) async {
    setState(() => _saving = true);
    var ok = false;
    try {
      await tryAction(
        context,
        () async {
          await Api.setNotificationPref(kind,
              enabled: enabled, silent: silent, mutedUntil: mutedUntil);
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
                kind: kind,
                enabled: enabled,
                silent: silent,
                mutedUntil: mutedUntil);
            _optimistic =
                _samePref(chosen, widget.pref) ? null : chosen;
          }
        });
      }
    }
  }

}
