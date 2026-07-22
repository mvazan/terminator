import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/chat_items.dart';
import 'package:terminator/domain/models.dart';

ChatMessage msg(String id, String user, DateTime at, [String body = 'ahoj']) =>
    ChatMessage(
      id: id,
      tournamentId: 't1',
      userId: user,
      body: body,
      createdAt: at,
    );

void main() {
  final noon = DateTime.utc(2026, 7, 21, 12, 0);

  test('day headers split messages by calendar day', () {
    final items = buildChatItems([
      msg('a', 'u1', noon),
      msg('b', 'u1', noon.add(const Duration(days: 1))),
    ], uid: 'u1');

    expect(items.whereType<DayHeaderItem>(), hasLength(2));
    expect(items.first, isA<DayHeaderItem>());
  });

  test('same author within 5 minutes chains into one group', () {
    final items = buildChatItems([
      msg('a', 'u1', noon),
      msg('b', 'u1', noon.add(const Duration(minutes: 2))),
      msg('c', 'u1', noon.add(const Duration(minutes: 3))),
    ], uid: 'me');

    final bubbles = items.whereType<MessageItem>().toList();
    expect(bubbles.map((b) => b.firstOfGroup), [true, false, false]);
    expect(bubbles.map((b) => b.lastOfGroup), [false, false, true]);
  });

  test('author change or a long pause breaks the group', () {
    final items = buildChatItems([
      msg('a', 'u1', noon),
      msg('b', 'u2', noon.add(const Duration(minutes: 1))),
      msg('c', 'u2', noon.add(const Duration(minutes: 20))),
    ], uid: 'me');

    final bubbles = items.whereType<MessageItem>().toList();
    expect(bubbles.map((b) => b.firstOfGroup), [true, true, true]);
    expect(bubbles.map((b) => b.lastOfGroup), [true, true, true]);
  });

  test('unread divider sits before the first unseen foreign message', () {
    final readAt = noon.add(const Duration(minutes: 1));
    final items = buildChatItems([
      msg('a', 'u1', noon), //                        read
      msg('b', 'u1', noon.add(const Duration(minutes: 2))), // unread
      msg('c', 'u1', noon.add(const Duration(minutes: 3))), // unread
    ], readAt: readAt, uid: 'me');

    expect(items.whereType<UnreadDividerItem>(), hasLength(1));
    final dividerIndex =
        items.indexWhere((i) => i is UnreadDividerItem);
    final after = items[dividerIndex + 1];
    expect(after, isA<MessageItem>());
    expect((after as MessageItem).message.id, 'b');
    // The divider also restarts the visual group.
    expect(after.firstOfGroup, isTrue);
    final before = items[dividerIndex - 1] as MessageItem;
    expect(before.lastOfGroup, isTrue);
  });

  test('my own messages never trigger the divider', () {
    final items = buildChatItems([
      msg('a', 'me', noon.add(const Duration(minutes: 5))),
    ], readAt: noon, uid: 'me');
    expect(items.whereType<UnreadDividerItem>(), isEmpty);
  });

  test('never-read chat puts the divider before the first foreign message',
      () {
    final items = buildChatItems([
      msg('a', 'u1', noon),
    ], readAt: null, uid: 'me');
    expect(items.first, isA<DayHeaderItem>());
    expect(items[1], isA<UnreadDividerItem>());
  });

  group('chatListTime', () {
    final now = DateTime(2026, 7, 22, 15, 0);

    test('today -> clock time', () {
      expect(chatListTime(DateTime(2026, 7, 22, 9, 5), now: now), '9:05');
    });

    test('yesterday -> včera', () {
      expect(chatListTime(DateTime(2026, 7, 21, 23, 59), now: now), 'včera');
    });

    test('older -> short day label', () {
      expect(chatListTime(DateTime(2026, 7, 19, 10, 0), now: now),
          'ne 19.7.');
    });
  });
}
