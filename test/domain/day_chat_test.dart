import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/day_chat.dart';
import 'package:terminator/domain/models.dart';

import 'helpers.dart';

void main() {
  final thu = Day(2026, 4, 23);
  final fri = Day(2026, 4, 24);
  // t1: slot s1 (thu), s2 (fri). Order o1 (creator 'org') orders both.
  final s1 = makeSlot('s1', thu, const HourMinute(18, 0));
  final s2 = makeSlot('s2', fri, const HourMinute(18, 0));

  Map<String, DayChatMembership> build({
    List<RosterEntry> rosters = const [],
    List<Availability> availability = const [],
    List<DayChatFan> fans = const [],
    List<DayChatLeaver> leavers = const [],
    OrderStatus status = OrderStatus.ordered,
    List<Slot> slots = const [],
  }) =>
      dayChatMembershipByChat(
        orders: [makeOrder(id: 'o1', tournamentId: 't1', status: status)],
        orderSlots: {
          'o1': {'s1': 1, 's2': 1},
        },
        slots: slots.isEmpty ? [s1, s2] : slots,
        rosters: rosters,
        availability: availability,
        fans: fans,
        leavers: leavers,
      );

  RosterEntry roster(String slotId, String uid) =>
      RosterEntry(id: '$slotId-$uid', slotId: slotId, addedBy: uid, userId: uid);

  test('creator is a member even with an empty roster (bootstrap)', () {
    final m = build();
    // makeOrder's creator is 'u1'; both days exist from the order's slots.
    expect(m[dayChatKey('t1', thu)]!.members, {'u1'});
    expect(m[dayChatKey('t1', fri)]!.members, {'u1'});
  });

  test('rostered players + creator are members', () {
    final m = build(rosters: [roster('s1', 'pavel'), roster('s2', 'milos')]);
    expect(m[dayChatKey('t1', thu)]!.members, containsAll(['pavel', 'u1']));
    expect(m[dayChatKey('t1', fri)]!.members, containsAll(['milos', 'u1']));
  });

  test('fan joins; rostered player stays even with a leaver row (roster wins)',
      () {
    final m = build(
      rosters: [roster('s1', 'pavel')],
      fans: [DayChatFan(tournamentId: 't1', day: thu, userId: 'fan')],
      leavers: [DayChatLeaver(tournamentId: 't1', day: thu, userId: 'pavel')],
    );
    final thursday = m[dayChatKey('t1', thu)]!;
    expect(thursday.contains('fan'), isTrue);
    expect(thursday.isFanOnly('fan'), isTrue);
    expect(thursday.canLeave('fan'), isTrue);
    // Rostered player stays despite the leaver row, and can't "leave".
    expect(thursday.contains('pavel'), isTrue);
    expect(thursday.canLeave('pavel'), isFalse);
  });

  test('creator-only can leave; a leaver row removes them', () {
    // makeOrder creator 'u1' isn't rostered here -> creator-only, can leave.
    final left = build(
      leavers: [DayChatLeaver(tournamentId: 't1', day: thu, userId: 'u1')],
    )[dayChatKey('t1', thu)]!;
    expect(left.contains('u1'), isFalse);
  });

  test('cancelled order alone = no day chat', () {
    expect(build(status: OrderStatus.cancelled), isEmpty);
  });

  test('a fan keeps the chat alive without an active order', () {
    final m = build(
      status: OrderStatus.cancelled,
      fans: [DayChatFan(tournamentId: 't1', day: thu, userId: 'fan')],
    );
    expect(m[dayChatKey('t1', thu)]!.members, {'fan'});
  });

  // Interest as a membership source — the pre-order day chat.
  test('ticked interest makes a member before any order exists', () {
    final m = build(
      status: OrderStatus.cancelled,
      availability: [const Availability(slotId: 's1', userId: 'pavel')],
    );
    final thursday = m[dayChatKey('t1', thu)]!;
    expect(thursday.members, {'pavel'});
    expect(thursday.roleOf('pavel'), DayChatRole.interested);
    expect(thursday.canLeave('pavel'), isTrue);
    // The other day has no members at all.
    expect(m[dayChatKey('t1', fri)], isNull);
  });

  test('interest keeps counting after the order is placed', () {
    // 'zajemce' ticked but wasn't rostered — still in, waiting for a spot.
    final thursday = build(
      rosters: [roster('s1', 'pavel')],
      availability: [const Availability(slotId: 's1', userId: 'zajemce')],
    )[dayChatKey('t1', thu)]!;
    expect(thursday.members, containsAll(['pavel', 'zajemce', 'u1']));
    expect(thursday.roleOf('zajemce'), DayChatRole.interested);
    // Rostered beats interested in the role label.
    expect(thursday.roleOf('pavel'), DayChatRole.player);
  });

  test('a leaver row beats interest, but a roster spot beats the leaver', () {
    final thursday = build(
      rosters: [roster('s1', 'pavel')],
      availability: [
        const Availability(slotId: 's1', userId: 'pavel'),
        const Availability(slotId: 's1', userId: 'zajemce'),
      ],
      leavers: [
        DayChatLeaver(tournamentId: 't1', day: thu, userId: 'zajemce'),
        DayChatLeaver(tournamentId: 't1', day: thu, userId: 'pavel'),
      ],
    )[dayChatKey('t1', thu)]!;
    expect(thursday.contains('zajemce'), isFalse);
    expect(thursday.contains('pavel'), isTrue);
  });

  test('interest in a cancelled start does not make a member', () {
    final cancelled = makeSlot('s1', thu, const HourMinute(18, 0),
        cancelledAt: DateTime(2026, 4, 20));
    final m = build(
      status: OrderStatus.cancelled,
      slots: [cancelled, s2],
      availability: [const Availability(slotId: 's1', userId: 'pavel')],
    );
    expect(m, isEmpty);
  });

  test('interest is per day — ticking Friday does not join Thursday', () {
    final m = build(
      status: OrderStatus.cancelled,
      availability: [const Availability(slotId: 's2', userId: 'pavel')],
    );
    expect(m[dayChatKey('t1', thu)], isNull);
    expect(m[dayChatKey('t1', fri)]!.members, {'pavel'});
  });
}
