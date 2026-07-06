/// Chat lifecycle policy.
///
/// Chats auto-lock (become read-only, move to the archive section) after
/// their subject has passed: the tournament chat after the tournament ends,
/// a day chat after its day is played — both plus a grace period. The exact
/// grace/purge policy is a deferred decision; this module keeps it in one
/// place so changing it later touches nothing else.
library;

import 'models.dart';

/// Days a chat stays open after its subject ends.
const int chatGraceDays = 3;

/// The day after which the chat locks (inclusive last open day).
Day chatOpenUntil({required Tournament tournament, Day? day}) =>
    (day ?? tournament.endsOn).addDays(chatGraceDays);

bool isChatLocked({
  required Tournament tournament,
  Day? day,
  required Day today,
}) =>
    today.isAfter(chatOpenUntil(tournament: tournament, day: day));
