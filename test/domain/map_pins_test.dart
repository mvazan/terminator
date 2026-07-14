import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/map_pins.dart';
import 'package:terminator/domain/models.dart';

import 'helpers.dart';

void main() {
  final today = Day(2026, 5, 15);

  Tournament t(String id, Day start, Day end) =>
      makeTournament(id: id, startsOn: start, endsOn: end);

  ({Tournament tournament, VenuePinState state})? pin(
    List<Tournament> ts, {
    Set<String> hidden = const {},
    Set<String> ticked = const {},
    Set<String> start = const {},
  }) =>
      venuePin(
        venueTournaments: ts,
        today: today,
        hiddenByMe: hidden,
        myTicked: ticked,
        myStart: start,
      );

  group('representative selection', () {
    final ongoing = t('on', Day(2026, 5, 14), Day(2026, 5, 16));
    final upcoming = t('up', Day(2026, 5, 20), Day(2026, 5, 21));
    final past = t('pa', Day(2026, 5, 1), Day(2026, 5, 2));

    test('ongoing wins over upcoming and past', () {
      expect(pin([past, upcoming, ongoing])!.tournament.id, 'on');
    });

    test('no ongoing -> nearest upcoming', () {
      final far = t('far', Day(2026, 6, 1), Day(2026, 6, 2));
      expect(pin([past, far, upcoming])!.tournament.id, 'up');
    });

    test('only past -> most recent', () {
      final older = t('old', Day(2026, 4, 1), Day(2026, 4, 2));
      expect(pin([older, past])!.tournament.id, 'pa');
    });

    test('empty -> null pin', () {
      expect(pin(const []), isNull);
    });

    test('ongoing picks the one ending soonest', () {
      final endsLater = t('late', Day(2026, 5, 10), Day(2026, 5, 30));
      final endsSooner = t('soon', Day(2026, 5, 10), Day(2026, 5, 16));
      expect(pin([endsLater, endsSooner])!.tournament.id, 'soon');
    });
  });

  group('pin state', () {
    final ongoing = t('on', Day(2026, 5, 14), Day(2026, 5, 16));
    final upcoming = t('up', Day(2026, 5, 20), Day(2026, 5, 21));
    final past = t('pa', Day(2026, 5, 1), Day(2026, 5, 2));

    test('hidden overrides everything', () {
      expect(pin([ongoing], hidden: {'on'}, ticked: {'on'})!.state,
          VenuePinState.hidden);
    });

    test('past is grey regardless of ticks', () {
      expect(pin([past], ticked: {'pa'})!.state, VenuePinState.past);
    });

    test('ongoing shades by my involvement', () {
      expect(pin([ongoing])!.state, VenuePinState.ongoingNone);
      expect(pin([ongoing], ticked: {'on'})!.state, VenuePinState.ongoingMine);
      expect(pin([ongoing], start: {'on'})!.state, VenuePinState.ongoingStart);
    });

    test('upcoming shades by my involvement', () {
      expect(pin([upcoming])!.state, VenuePinState.upcomingNone);
      expect(
          pin([upcoming], ticked: {'up'})!.state, VenuePinState.upcomingMine);
      expect(
          pin([upcoming], start: {'up'})!.state, VenuePinState.upcomingStart);
    });

    test('start beats a mere tick', () {
      expect(pin([ongoing], ticked: {'on'}, start: {'on'})!.state,
          VenuePinState.ongoingStart);
    });
  });
}
