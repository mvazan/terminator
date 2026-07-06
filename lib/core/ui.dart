/// Small shared UI helpers: Czech date labels, snackbars, name lookups.
library;

import 'package:flutter/material.dart';

import '../domain/models.dart';

const _weekdaysShort = ['po', 'út', 'st', 'čt', 'pá', 'so', 'ne'];
const _weekdaysFull = [
  'pondělí', 'úterý', 'středa', 'čtvrtek', 'pátek', 'sobota', 'neděle',
];

/// "čt 23.4."
String dayLabel(Day d) => '${_weekdaysShort[d.weekday - 1]} ${d.day}.${d.month}.';

/// "čtvrtek 23. 4."
String dayFull(Day d) =>
    '${_weekdaysFull[d.weekday - 1]} ${d.day}. ${d.month}.';

/// "20.4.–3.5."
String rangeLabel(Day from, Day to) =>
    '${from.day}.${from.month}.–${to.day}.${to.month}.';

Day today() => Day.fromDateTime(DateTime.now());

void snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

/// Runs [action]; on failure shows the error as a snackbar.
Future<void> tryAction(BuildContext context, Future<void> Function() action,
    {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) snack(context, success);
  } catch (e) {
    if (context.mounted) snack(context, 'Nepovedlo se: $e');
  }
}

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
            _weekdaysShort[day.weekday - 1],
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
