import 'package:terminator/domain/models.dart';

Tournament makeTournament({
  String id = 't1',
  String name = 'Vracov Cup',
  String venueId = 'v1',
  TournamentKind kind = TournamentKind.dvojice,
  Discipline? discipline,
  required Day startsOn,
  required Day endsOn,
  int minPlayers = 2,
}) =>
    Tournament(
      id: id,
      name: name,
      venueId: venueId,
      kind: kind,
      discipline: discipline,
      startsOn: startsOn,
      endsOn: endsOn,
      minPlayers: minPlayers,
      contactEmail: 'organizer@example.com',
      contactPhone: '',
      sourceUrl: '',
      notes: '',
      createdBy: 'u1',
      createdAt: DateTime.utc(2026, 1, 1),
    );

Slot makeSlot(String id, Day date, HourMinute time, {String tournamentId = 't1'}) =>
    Slot(id: id, tournamentId: tournamentId, date: date, time: time);
