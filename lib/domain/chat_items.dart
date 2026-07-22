/// Render model of a chat: raw messages (ascending) become day headers,
/// author groups and the "new messages" divider — pure, so the widget layer
/// just paints.
library;

import 'models.dart';

sealed class ChatItem {
  const ChatItem();
}

class DayHeaderItem extends ChatItem {
  const DayHeaderItem(this.day);
  final Day day;
}

/// "Nové zprávy" line — sits before the first message the user hasn't seen.
class UnreadDividerItem extends ChatItem {
  const UnreadDividerItem();
}

class MessageItem extends ChatItem {
  const MessageItem(
    this.message, {
    required this.firstOfGroup,
    required this.lastOfGroup,
  });

  final ChatMessage message;

  /// First bubble of an author run — shows the author name.
  final bool firstOfGroup;

  /// Last bubble of an author run — shows the timestamp.
  final bool lastOfGroup;
}

/// Messages of the same author within this gap chain into one visual group.
const chatGroupGap = Duration(minutes: 5);

/// Builds the render list. [messages] ascending by time. [readAt] is when the
/// user last read this chat BEFORE opening it now (null = never) — messages
/// after it from OTHER people get the unread divider. [uid] = current user.
List<ChatItem> buildChatItems(
  List<ChatMessage> messages, {
  DateTime? readAt,
  String? uid,
}) {
  Day dayOf(ChatMessage m) => Day.fromDateTime(m.createdAt.toLocal());
  bool chains(ChatMessage a, ChatMessage b) =>
      a.userId == b.userId &&
      b.createdAt.difference(a.createdAt) < chatGroupGap &&
      dayOf(a) == dayOf(b);
  bool startsUnread(ChatMessage m) =>
      m.userId != uid && (readAt == null || m.createdAt.isAfter(readAt));

  final items = <ChatItem>[];
  var dividerPlaced = false;
  for (var i = 0; i < messages.length; i++) {
    final m = messages[i];
    final prev = i > 0 ? messages[i - 1] : null;
    final next = i + 1 < messages.length ? messages[i + 1] : null;

    final newDay = prev == null || dayOf(m) != dayOf(prev);
    if (newDay) items.add(DayHeaderItem(dayOf(m)));

    final unreadHere = !dividerPlaced && startsUnread(m);
    if (unreadHere) {
      dividerPlaced = true;
      items.add(const UnreadDividerItem());
    }

    // Day headers and the divider restart the visual group; the same breaks
    // looked at from the other side end it.
    final chainsPrev = prev != null && chains(prev, m) && !newDay && !unreadHere;
    final nextBreaks = next == null ||
        dayOf(next) != dayOf(m) ||
        (!dividerPlaced && startsUnread(next));
    final chainsNext = next != null && chains(m, next) && !nextBreaks;
    items.add(MessageItem(
      m,
      firstOfGroup: !chainsPrev,
      lastOfGroup: !chainsNext,
    ));
  }
  return items;
}

const _weekdaysShort = ['po', 'út', 'st', 'čt', 'pá', 'so', 'ne'];

/// Chat-list tile timestamp: "14:32" today, "včera" yesterday, otherwise a
/// short day label like "po 21.7.". (Weekday names duplicated from core/ui
/// on purpose — domain stays Flutter-free.)
String chatListTime(DateTime at, {required DateTime now}) {
  final local = at.toLocal();
  final atDay = Day.fromDateTime(local);
  final nowDay = Day.fromDateTime(now.toLocal());
  if (atDay == nowDay) {
    return '${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  }
  if (atDay == nowDay.addDays(-1)) return 'včera';
  return '${_weekdaysShort[atDay.weekday - 1]} ${atDay.day}.${atDay.month}.';
}
