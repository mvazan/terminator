import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/push/chat_notification_match.dart';

/// Payload as Push._showFromData stores it: the whole FCM data map, chat
/// identity riding next to title/body/channel.
String _payload(Map<String, dynamic> data) => jsonEncode({
      'title': 'Turnaj — so 5.9.',
      'body': 'Pepa: jedu',
      'channel': 'terminator',
      ...data,
    });

void main() {
  final day = Day(2026, 9, 5);

  test('turnajový chat: match jen na stejný turnaj bez dne', () {
    final p = _payload({'kind': 'chat', 'tournament_id': 't1'});
    expect(chatPayloadMatches(p, tournamentId: 't1'), isTrue);
    expect(chatPayloadMatches(p, tournamentId: 't2'), isFalse);
    expect(chatPayloadMatches(p, tournamentId: 't1', day: day), isFalse);
    expect(chatPayloadMatches(p, tournamentId: 't1', team: true), isFalse);
  });

  test('denní chat: match jen na stejný turnaj + den', () {
    final p = _payload(
        {'kind': 'chat', 'tournament_id': 't1', 'day': '2026-09-05'});
    expect(chatPayloadMatches(p, tournamentId: 't1', day: day), isTrue);
    expect(chatPayloadMatches(p, tournamentId: 't1'), isFalse);
    expect(chatPayloadMatches(p, tournamentId: 't1', day: Day(2026, 9, 6)),
        isFalse);
    expect(chatPayloadMatches(p, tournamentId: 't2', day: day), isFalse);
  });

  test('týmový chat: match jen na team identitu', () {
    final p = _payload({'kind': 'team_chat'});
    expect(
        chatPayloadMatches(p, tournamentId: teamChatSentinelId, team: true),
        isTrue);
    expect(chatPayloadMatches(p, tournamentId: 't1'), isFalse);
    expect(chatPayloadMatches(p, tournamentId: teamChatSentinelId), isFalse);
  });

  test('jiný kind nikdy nematchne', () {
    final p = _payload({'kind': 'order', 'tournament_id': 't1'});
    expect(chatPayloadMatches(p, tournamentId: 't1'), isFalse);
    expect(chatPayloadMatches(p, tournamentId: 't1', team: true), isFalse);
  });

  test('null / prázdný / rozbitý payload → false', () {
    expect(chatPayloadMatches(null, tournamentId: 't1'), isFalse);
    expect(chatPayloadMatches('', tournamentId: 't1'), isFalse);
    expect(chatPayloadMatches('not json', tournamentId: 't1'), isFalse);
    expect(chatPayloadMatches('[1,2]', tournamentId: 't1'), isFalse);
  });
}
