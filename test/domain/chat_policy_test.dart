import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/chat_policy.dart';
import 'package:terminator/domain/models.dart';

import 'helpers.dart';

void main() {
  final tournament = makeTournament(
    startsOn: Day(2026, 4, 20),
    endsOn: Day(2026, 5, 3),
  );

  test('tournament chat stays open through the grace period', () {
    expect(
      isChatLocked(tournament: tournament, today: Day(2026, 5, 3)),
      isFalse,
    );
    // Last open day: ends_on + 3 days grace.
    expect(
      isChatLocked(tournament: tournament, today: Day(2026, 5, 6)),
      isFalse,
    );
    expect(
      isChatLocked(tournament: tournament, today: Day(2026, 5, 7)),
      isTrue,
    );
  });

  test('day chat locks relative to its own day, not the tournament end', () {
    final playedDay = Day(2026, 4, 22);
    expect(
      isChatLocked(tournament: tournament, day: playedDay, today: Day(2026, 4, 25)),
      isFalse,
    );
    expect(
      isChatLocked(tournament: tournament, day: playedDay, today: Day(2026, 4, 26)),
      isTrue,
    );
  });

  test('TournamentKind: only tandem puts 2 players on one lane', () {
    expect(TournamentKind.jednotlivci.playersPerLane, 1);
    expect(TournamentKind.dvojice.playersPerLane, 1);
    expect(TournamentKind.ctverice.playersPerLane, 1);
    expect(TournamentKind.tandem.playersPerLane, 2);
    expect(TournamentKind.tryParse('tandem'), TournamentKind.tandem);
    expect(TournamentKind.tryParse('neznámý'), isNull);
  });

  test('models: HourMinute and Day parse Postgres formats', () {
    expect(HourMinute.parse('16:30:00'), const HourMinute(16, 30));
    expect(HourMinute.parse('9:05'), const HourMinute(9, 5));
    expect(const HourMinute(16, 30).toSql(), '16:30:00');
    expect(Day.parse('2026-04-20').toSql(), '2026-04-20');
    expect(Day(2026, 4, 20).weekday, DateTime.monday);
  });
}
