import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/chat_reactions.dart';
import 'package:terminator/domain/models.dart';

Reaction _r(String messageId, String userId, String emoji) => Reaction(
      id: '$messageId|$userId|$emoji',
      messageId: messageId,
      userId: userId,
      emoji: emoji,
    );

void main() {
  const uid = 'me';
  final raw = {
    'm1': [_r('m1', 'other', '👍')],
    'm2': [_r('m2', uid, '❤️')],
  };

  test('add-op přidá moji reakci hned; cizí zprávy nedotčené', () {
    final out = applyPendingReactions(
        raw, [const PendingReaction('m1', '👍', add: true)], uid);
    expect(out['m1']!.map((r) => '${r.userId}${r.emoji}'),
        containsAll(['other👍', 'me👍']));
    expect(out['m2'], same(raw['m2']));
    expect(raw['m1']!.length, 1); // vstup nemutuje
  });

  test('add-op nezdvojí reakci, kterou už stream má', () {
    final out = applyPendingReactions(
        raw, [const PendingReaction('m2', '❤️', add: true)], uid);
    expect(out['m2']!.length, 1);
  });

  test('remove-op odfiltruje moji reakci hned', () {
    final out = applyPendingReactions(
        raw, [const PendingReaction('m2', '❤️', add: false)], uid);
    expect(out['m2'], isEmpty);
    expect(raw['m2']!.length, 1); // vstup nemutuje
  });

  test('reactionReflected: add potvrzený až když raw reakci má', () {
    const op = PendingReaction('m1', '👍', add: true);
    expect(reactionReflected(raw, op, uid), isFalse);
    final confirmed = {
      'm1': [_r('m1', 'other', '👍'), _r('m1', uid, '👍')],
    };
    expect(reactionReflected(confirmed, op, uid), isTrue);
  });

  test('reactionReflected: remove potvrzený až když raw reakci nemá', () {
    const op = PendingReaction('m2', '❤️', add: false);
    expect(reactionReflected(raw, op, uid), isFalse);
    expect(reactionReflected({'m2': const []}, op, uid), isTrue);
    expect(reactionReflected(const {}, op, uid), isTrue);
  });
}
