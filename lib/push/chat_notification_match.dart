/// Matching push payloadů na identitu chatu — podle něj Push maže z lišty
/// notifikace právě přečteného chatu. Kontrakt payloadu (kind +
/// tournament_id + day) plní notify EF (case messages/team_messages);
/// při změně drž obojí v syncu.
library;

import 'dart:convert';

import '../domain/models.dart';

/// True když push [data] (FCM data / payload notifikace) patří chatu
/// [tournamentId]+[day], resp. týmovému chatu při [team]. U [team] se
/// [tournamentId] ignoruje (volající předává sentinel [teamChatSentinelId]).
bool chatDataMatches(
  Map<String, dynamic> data, {
  required String tournamentId,
  Day? day,
  bool team = false,
}) {
  if (team) return data['kind'] == 'team_chat';
  if (data['kind'] != 'chat') return false;
  if (data['tournament_id'] != tournamentId) return false;
  final payloadDay = data['day'];
  return day == null ? payloadDay == null : payloadDay == day.toSql();
}

/// [chatDataMatches] nad JSON payloadem uloženým u notifikace
/// (Push._showFromData ukládá jsonEncode celých dat). Cokoli nečitelného
/// → false.
bool chatPayloadMatches(
  String? payloadJson, {
  required String tournamentId,
  Day? day,
  bool team = false,
}) {
  if (payloadJson == null || payloadJson.isEmpty) return false;
  try {
    final decoded = jsonDecode(payloadJson);
    if (decoded is! Map) return false;
    return chatDataMatches(decoded.cast<String, dynamic>(),
        tournamentId: tournamentId, day: day, team: team);
  } catch (_) {
    return false;
  }
}
