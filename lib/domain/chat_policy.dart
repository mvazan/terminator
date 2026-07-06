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

/// Identifies one chat: tournament chat (day == null) or a day chat.
class ChatRef {
  const ChatRef(this.tournamentId, [this.day]);

  final String tournamentId;
  final Day? day;

  bool get isTournamentChat => day == null;

  @override
  bool operator ==(Object other) =>
      other is ChatRef && other.tournamentId == tournamentId && other.day == day;

  @override
  int get hashCode => Object.hash(tournamentId, day);
}

/// The day after which the chat locks (inclusive last open day).
Day chatOpenUntil({required Tournament tournament, Day? day}) =>
    (day ?? tournament.endsOn).addDays(chatGraceDays);

bool isChatLocked({
  required Tournament tournament,
  Day? day,
  required Day today,
}) =>
    today.isAfter(chatOpenUntil(tournament: tournament, day: day));
