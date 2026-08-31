# Drobnosti UI — chronologické objednávky, optimistic reakce, čára dneška

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Tři nezávislé mikro-úkoly, každý = TDD + samostatný commit.

**Goal:** (1) Objednávky v detailu turnaje chronologicky podle prvního startu; (2) reakce v chatu se projeví okamžitě (optimistic update, vzor _Pending zpráv); (3) sezónní kalendář ukazuje svislou čáru dneška přes všechny řádky.

**Global constraints:** komentáře dle stylu souboru; commit po změně, bez pushe; `flutter analyze` čisté + celá suite zelená po každém úkolu.

---

### Task 1: Objednávky chronologicky

**Files:** Create `lib/domain/order_sort.dart` + `test/domain/order_sort_test.dart`; Modify `lib/features/tournaments/tournament_detail_screen.dart`.

Čistá funkce (řadí kopii):

```dart
List<Order> ordersByFirstStart(List<Order> orders,
    {required Map<String, Map<String, int>> orderSlots,
     required Map<String, Slot> slotById})
```

Klíč objednávky = nejdřívější (date, time) jejích slotů přes `compareDayTime`; objednávky bez rozpoznatelných slotů až nakonec; shoda → starší `createdAt` dřív. Testy: řazení napříč dny i časy; bez slotů nakonec; tie-break createdAt; vstupní pořadí (newest-first z provideru) se přepíše.

Detail screen: po sestavení `allSlots` postavit `slotById` a v sekci Objednávky iterovat seřazenou kopii místo `orders` (globální provider zůstává newest-first — ostatní obrazovky beze změny).

### Task 2: Optimistic reakce

**Files:** Create `lib/domain/chat_reactions.dart` + `test/domain/chat_reactions_test.dart`; Modify `lib/features/chats/chat_screen.dart`.

Čisté jádro:

```dart
class PendingReaction { messageId; emoji; add; }
bool reactionReflected(Map<String, List<Reaction>> raw, PendingReaction op, String uid);
Map<String, List<Reaction>> applyPendingReactions(
    Map<String, List<Reaction>> raw, List<PendingReaction> pending, String uid);
```

`reactionReflected`: add-op je potvrzený, když raw obsahuje (uid, emoji) u zprávy; remove-op když neobsahuje. `applyPendingReactions`: add → přidá syntetickou Reaction(uid, emoji) pokud chybí; remove → odfiltruje; raw nemutuje. Testy: add/remove aplikace, idempotence (už přítomná reakce se nezdvojí), potvrzené ops, cizí zprávy nedotčené.

ChatScreen: stav `_pendingReactions`; v buildu nejdřív `removeWhere(reactionReflected(raw, op, uid))`, pak overlay → `reactions` používané pro render I pro výpočet `mine`. `_toggleReaction(message, emoji)` (bez třetího parametru, oba call-sites upravit): `mine` z overlaynutého stavu, `setState` přidá op, `tryAction` → při `false` revert (op odebrat). Haptika zůstává.

### Task 3: Čára dneška v sezónním kalendáři

**Files:** Modify `lib/domain/timeline.dart` + `test/domain/timeline_test.dart`; Modify `lib/features/tournaments/timeline_screen.dart`.

Domain (TDD):

```dart
/// Offset [day] ve dnech od prvního pondělí timeline (0 = to pondělí),
/// null když je timeline prázdná nebo den mimo zobrazené týdny.
int? dayOffsetOf(Day day)  // metoda Timeline
```

Testy: pondělí první kolony → 0; den uvnitř → správný offset přes víc týdnů; před rozsahem / za posledním nedělním dnem / prázdná timeline → null.

UI: řádky obalit `Stack`em; při `dayOffsetOf(today) != null` navrch `Positioned` svislá čára `width: 2`, `left: _labelWidth + (offset + 0.5) * _cellWidth / 7 - 1`, přes celou výšku řádků, v `IgnorePointer` (taps na řádky fungují dál). Barva `const _todayLineColor = Color(0xFF1565C0)` — sytá modrá: červená je obsazená markerem „hraju", primary tématu je bordó (skoro červená), pastelové bary se nepletou.

### Task 4: Závěr

`flutter analyze` + celá suite; commit per task proběhl průběžně.
