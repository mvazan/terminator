/// Small shared UI helpers: Czech date labels, snackbars, dialogs, external
/// launches, name lookups.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/providers.dart';
import '../domain/models.dart';

export '../domain/models.dart' show rangeLabel;

const weekdaysShort = ['po', 'út', 'st', 'čt', 'pá', 'so', 'ne'];

const _diacritics = 'áäčďéěíĺľňóôřŕšťúůýžÁÄČĎÉĚÍĹĽŇÓÔŘŔŠŤÚŮÝŽ';
const _plain = 'aacdeeillnoorrstuuyzAACDEEILLNOORRSTUUYZ';

/// Lowercased, diacritics-stripped form for search matching ("Vážan" and
/// "vazan" find each other).
String searchFold(String s) {
  final buffer = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    final i = _diacritics.indexOf(ch);
    buffer.write(i >= 0 ? _plain[i] : ch);
  }
  return buffer.toString().toLowerCase();
}

/// Czech-declined lane count: "1 dráha", "2 dráhy", "5 drah".
String lanesLabel(int n) {
  final word = n == 1
      ? 'dráha'
      : (n >= 2 && n <= 4 ? 'dráhy' : 'drah');
  return '$n $word';
}

/// Czech-declined people count: "1 člověk", "2 lidé", "5 lidí".
String peopleLabel(int n) {
  final word = n == 1 ? 'člověk' : (n >= 2 && n <= 4 ? 'lidé' : 'lidí');
  return '$n $word';
}
const _weekdaysFull = [
  'pondělí', 'úterý', 'středa', 'čtvrtek', 'pátek', 'sobota', 'neděle',
];

/// "čt 23.4."
String dayLabel(Day d) => '${weekdaysShort[d.weekday - 1]} ${d.day}.${d.month}.';

/// "čtvrtek 23. 4."
String dayFull(Day d) =>
    '${_weekdaysFull[d.weekday - 1]} ${d.day}. ${d.month}.';

Day today() => Day.fromDateTime(DateTime.now());

void snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

/// True when [e] smells like a dead/absent connection rather than a bug —
/// DNS failures, refused/unreachable sockets, and Supabase's retryable
/// fetch wrapper around them.
bool isOfflineError(Object e) {
  final s = '$e';
  return s.contains('SocketException') ||
      s.contains('Failed host lookup') ||
      s.contains('ClientException') ||
      s.contains('AuthRetryableFetchException') ||
      s.contains('Connection refused') ||
      s.contains('Network is unreachable') ||
      s.contains('Connection reset') ||
      s.contains('Software caused connection abort');
}

const offlineMessage =
    'Vypadá to, že jsi offline — zkontroluj připojení a zkus to znovu.';

/// User-facing message for [e]: friendly for connectivity problems, raw
/// (prefixed) for everything else so real bugs stay diagnosable.
String friendlyError(Object e) =>
    isOfflineError(e) ? offlineMessage : 'Nepovedlo se: $e';

/// Runs [action]; on failure shows the error as a snackbar.
/// Returns true when the action succeeded.
///
/// [timeout] guards against a dead/slow connection — Supabase calls have no
/// timeout of their own, so without this a tap can hang forever. The
/// underlying call isn't cancelled; if it lands late, the realtime echo
/// reconciles the UI (same trust model as everywhere else).
Future<bool> tryAction(BuildContext context, Future<void> Function() action,
    {String? success, Duration timeout = const Duration(seconds: 10)}) async {
  try {
    await action().timeout(timeout);
    if (success != null && context.mounted) snack(context, success);
    return true;
  } on TimeoutException {
    if (context.mounted) {
      snack(context,
          'Nepovedlo se — server neodpovídá. Zkontroluj připojení.');
    }
    return false;
  } catch (e, stack) {
    // Offline is the user's situation, not a defect — friendly message,
    // no Sentry noise.
    if (isOfflineError(e)) {
      if (context.mounted) snack(context, offlineMessage);
      return false;
    }
    // Report the swallowed failure as a non-fatal (scrape/Supabase errors
    // surface here); no-op when Sentry isn't configured.
    if (AppConfig.hasSentry) {
      await Sentry.captureException(e, stackTrace: stack);
    }
    if (context.mounted) snack(context, 'Nepovedlo se: $e');
    return false;
  }
}

/// Standard confirm dialog; resolves to true when [confirmLabel] was tapped.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Ano',
  String cancelLabel = 'Zrušit',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(cancelLabel)),
        FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel)),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Confirms and signs the user out. Shared by every "Odhlásit se" entry point.
Future<void> confirmSignOut(BuildContext context) async {
  final ok = await confirmDialog(
    context,
    title: 'Odhlásit se?',
    message: 'Budeš se muset znovu přihlásit e-mailem.',
    confirmLabel: 'Odhlásit se',
  );
  if (ok) await Api.signOut();
}

/// Single-field text prompt; resolves to the trimmed input, or null on cancel.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? hint,
  String? initial,
  String confirmLabel = 'Uložit',
  TextInputType? keyboardType,
  String? suffixText,
}) async {
  final controller = TextEditingController(text: initial);
  try {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboardType,
          decoration: InputDecoration(hintText: hint, suffixText: suffixText),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Zrušit')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result;
  } finally {
    controller.dispose();
  }
}

void launchEmail(String address) =>
    _launchExternal(Uri.parse('mailto:$address'));

void launchPhone(String number) =>
    _launchExternal(Uri.parse('tel:${number.replaceAll(' ', '')}'));

void launchWeb(String url) => _launchExternal(
    Uri.parse(url.contains('://') ? url : 'https://$url'));

/// Opens the address in the device's default maps app (navigation). The
/// `geo:` URI is the Android standard — the system shows the app chooser
/// (Google Maps, Mapy.cz, Waze…) and searches for the address.
void launchMap(String address) => _launchExternal(
    Uri.parse('geo:0,0?q=${Uri.encodeComponent(address)}'));

void _launchExternal(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

String memberName(List<Profile> members, String userId) {
  for (final m in members) {
    if (m.id == userId) return m.displayName;
  }
  return '?';
}

String rosterEntryName(RosterEntry entry, List<Profile> members) =>
    entry.isGuest ? '${entry.guestName} *' : memberName(members, entry.userId!);

/// Rounded calendar-leaf date badge used in list items.
class DateBadge extends StatelessWidget {
  const DateBadge(this.day, {super.key});

  final Day day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      // FittedBox keeps the two lines inside the fixed 48 px box even with
      // taller fonts (accessibility scale, the test environment's Ahem).
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}.${day.month}.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: scheme.onPrimaryContainer,
              ),
            ),
            Text(
              weekdaysShort[day.weekday - 1],
              style: TextStyle(
                fontSize: 11,
                color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
