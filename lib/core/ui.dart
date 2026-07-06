/// Small shared UI helpers: Czech date labels, snackbars, dialogs, external
/// launches, name lookups.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/models.dart';

export '../domain/models.dart' show rangeLabel;

const weekdaysShort = ['po', 'út', 'st', 'čt', 'pá', 'so', 'ne'];
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

/// Runs [action]; on failure shows the error as a snackbar.
/// Returns true when the action succeeded.
Future<bool> tryAction(BuildContext context, Future<void> Function() action,
    {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) snack(context, success);
    return true;
  } catch (e) {
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
    );
  }
}
