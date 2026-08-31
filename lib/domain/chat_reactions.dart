/// Optimistic reakce v chatu: ťuknutí se vykreslí hned a stream ho potvrdí
/// (stejný princip jako _Pending zprávy v ChatScreen).
library;

import 'models.dart';

/// Jedna zatím nepotvrzená reakce aktuálního uživatele.
class PendingReaction {
  const PendingReaction(this.messageId, this.emoji, {required this.add});

  final String messageId;
  final String emoji;

  /// true = přidávám, false = odebírám.
  final bool add;
}

/// True když už stream [raw] operaci odráží — pak si ji ChatScreen smaže
/// z pending seznamu.
bool reactionReflected(
    Map<String, List<Reaction>> raw, PendingReaction op, String uid) {
  final mine = (raw[op.messageId] ?? const [])
      .any((r) => r.userId == uid && r.emoji == op.emoji);
  return op.add ? mine : !mine;
}

/// Kopie [raw] s aplikovanými [pending] operacemi uživatele [uid]; add
/// nezdvojí už přítomnou reakci, vstup se nemutuje a zprávy bez operací
/// sdílí původní seznamy.
Map<String, List<Reaction>> applyPendingReactions(
  Map<String, List<Reaction>> raw,
  List<PendingReaction> pending,
  String uid,
) {
  if (pending.isEmpty) return raw;
  final out = Map.of(raw);
  for (final op in pending) {
    final current = out[op.messageId] ?? const <Reaction>[];
    if (op.add) {
      if (current.any((r) => r.userId == uid && r.emoji == op.emoji)) continue;
      out[op.messageId] = [
        ...current,
        Reaction(
          id: 'pending|${op.messageId}|${op.emoji}',
          messageId: op.messageId,
          userId: uid,
          emoji: op.emoji,
        ),
      ];
    } else {
      out[op.messageId] = [
        for (final r in current)
          if (!(r.userId == uid && r.emoji == op.emoji)) r,
      ];
    }
  }
  return out;
}
