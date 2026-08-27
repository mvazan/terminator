# Chat notifikace v sync s přečtením — implementační plán

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lišta Androidu drží nejvýš jednu notifikaci na chat a zmizí v momentě, kdy si člověk chat přečte — jakoukoli cestou.

**Architecture:** Server (EF `notify`) tagem zajistí nahrazování (jedna položka na chat). Klient maže položky chatu podle **payloadu** v okamžiku `markRead` (jediné místo, které už dnes ví, že je chat přečtený), otevřený chat příchozí push nekreslí a inline „Odpovědět" po odeslání chat uklidí. Spec: `docs/superpowers/specs/2026-08-27-chat-notification-sync-design.md`.

**Tech Stack:** Flutter/Dart, flutter_local_notifications 22.0.1 (`cancel({required int id, String? tag})`, `getActiveNotifications()` na hlavním pluginu, `ActiveNotification.payload/.tag`), Supabase Edge Function (Deno/TS).

## Global Constraints

- Jazyk komentářů: čeština/angličtina podle okolního souboru (push.dart anglicky, EF anglicky+česky mix — drž styl okolí).
- Commit po každé logické změně, žádný push (standing pravidlo uživatele).
- TDD u čisté logiky (matcher); plugin/UI vrstva je tenká a kryje ji analyze + celá suite.
- iOS: nic neřešit, jen no-op bezpečnost (try/catch) — evidence v IOS.md už existuje.
- `flutter analyze` bez findings a `flutter test` zelené po každém tasku.

---

### Task 1: Matcher — čistá funkce „patří payload tomuto chatu?"

**Files:**
- Create: `lib/push/chat_notification_match.dart`
- Test: `test/push/chat_notification_match_test.dart`

**Interfaces:**
- Consumes: `Day` z `package:terminator/domain/models.dart` (má `toSql()`).
- Produces:
  - `bool chatDataMatches(Map<String, dynamic> data, {required String tournamentId, Day? day, bool team = false})`
  - `bool chatPayloadMatches(String? payloadJson, {required String tournamentId, Day? day, bool team = false})`
  - Sémantika: `team: true` → `kind == 'team_chat'` (tournamentId se ignoruje, volající předává sentinel `teamChatId`); jinak `kind == 'chat'` && `tournament_id == tournamentId` && (`day == null` → payload bez `day`; jinak `payload['day'] == day.toSql()`). Rozbitý/chybějící JSON → `false`.

- [ ] **Step 1: Napiš failing testy**

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:terminator/domain/models.dart';
import 'package:terminator/push/chat_notification_match.dart';

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
    expect(chatPayloadMatches(p, tournamentId: teamChatId, team: true), isTrue);
    expect(chatPayloadMatches(p, tournamentId: 't1'), isFalse);
  });

  test('jiný kind nikdy nematchne', () {
    final p = _payload({'kind': 'order', 'tournament_id': 't1'});
    expect(chatPayloadMatches(p, tournamentId: 't1'), isFalse);
  });

  test('null / prázdný / rozbitý payload → false', () {
    expect(chatPayloadMatches(null, tournamentId: 't1'), isFalse);
    expect(chatPayloadMatches('', tournamentId: 't1'), isFalse);
    expect(chatPayloadMatches('not json', tournamentId: 't1'), isFalse);
    expect(chatPayloadMatches('[1,2]', tournamentId: 't1'), isFalse);
  });
}
```

- [ ] **Step 2: Ověř, že failují**

Run: `flutter test test/push/chat_notification_match_test.dart`
Expected: compile error „chat_notification_match.dart not found" — vytvoř prázdný soubor se signaturami vracejícími `false`, znovu spusť a sleduj assertion faily (ne compile error) u match-true případů.

- [ ] **Step 3: Implementace**

```dart
/// Matching push payloadů na identitu chatu — podle něj Push maže z lišty
/// notifikace právě přečteného chatu. Kontrakt payloadu (kind +
/// tournament_id + day) plní notify EF (case messages/team_messages);
/// při změně drž obojí v syncu.
library;

import 'dart:convert';

import '../domain/models.dart';

/// True když push [data] (FCM data / payload notifikace) patří chatu
/// [tournamentId]+[day], resp. týmovému chatu při [team]. U [team] se
/// [tournamentId] ignoruje (volající předává sentinel [teamChatId]).
bool chatDataMatches(
  Map<String, dynamic> data, {
  required String tournamentId,
  Day? day,
  bool team = false,
}) {
  if (team) return data['kind'] == 'team_chat';
  if (data['kind'] != 'chat') return false;
  if (data['tournament_id'] != tournamentId) return false;
  final payloadDay = data['day'];
  return day == null ? payloadDay == null : payloadDay == day.toSql();
}

/// [chatDataMatches] nad JSON payloadem uloženým u notifikace
/// (Push._showFromData ukládá jsonEncode celých dat). Cokoli nečitelného
/// → false.
bool chatPayloadMatches(
  String? payloadJson, {
  required String tournamentId,
  Day? day,
  bool team = false,
}) {
  if (payloadJson == null || payloadJson.isEmpty) return false;
  try {
    final decoded = jsonDecode(payloadJson);
    if (decoded is! Map) return false;
    return chatDataMatches(decoded.cast<String, dynamic>(),
        tournamentId: tournamentId, day: day, team: team);
  } catch (_) {
    return false;
  }
}
```

Pozn.: `teamChatId` v testu — exportuje ho `domain/models.dart`? Je to `teamChatSentinelId` konstanta re-exportovaná v providers (`const teamChatId = teamChatSentinelId;`). Pokud test import nevidí, importuj v testu tu konstantu odtud, kde reálně žije (najdi `teamChatSentinelId` grepem); matcher sám ji NEPOTŘEBUJE (team větev tournamentId ignoruje).

- [ ] **Step 4: Testy zelené**

Run: `flutter test test/push/chat_notification_match_test.dart`
Expected: All tests passed.

- [ ] **Step 5: Commit**

```bash
git add lib/push/chat_notification_match.dart test/push/chat_notification_match_test.dart
git commit -m "feat(push): matcher payloadů chat notifikací"
```

---

### Task 2: `Push.clearChatNotifications` + úklid po inline odpovědi

**Files:**
- Modify: `lib/push/push.dart` (import matcheru; nová metoda; rozšíření `sendReplyFromNotification`)

**Interfaces:**
- Consumes: `chatPayloadMatches` z Task 1; `_local` (FlutterLocalNotificationsPlugin), `cancel({required int id, String? tag})`, `getActiveNotifications()`.
- Produces: `static Future<void> clearChatNotifications({required String tournamentId, Day? day, bool team = false})` — volá Task 3.

- [ ] **Step 1: Metoda v `Push`** (vedle `_showFromData`)

```dart
  /// Smaže z lišty notifikace daného chatu — volá se v momentě přečtení
  /// (otevřený chat v ChatScreen, nebo odeslaná inline odpověď). Match jde
  /// podle payloadu, ne tagu, takže uklidí i pushe doručené před tím, než
  /// server začal tagovat. Best-effort: bez Androidu / bez notifikací tiše
  /// nic (iOS ekvivalent viz IOS.md).
  static Future<void> clearChatNotifications({
    required String tournamentId,
    Day? day,
    bool team = false,
  }) async {
    try {
      final active = await _local.getActiveNotifications();
      for (final n in active) {
        final id = n.id;
        if (id == null) continue;
        if (chatPayloadMatches(n.payload,
            tournamentId: tournamentId, day: day, team: team)) {
          await _local.cancel(id: id, tag: n.tag);
        }
      }
    } catch (e) {
      debugPrint('clearChatNotifications failed: $e');
    }
  }
```

Import: `import 'chat_notification_match.dart';`

- [ ] **Step 2: Úklid po inline odpovědi** — `sendReplyFromNotification` po každém úspěšném send:

```dart
  static Future<void> sendReplyFromNotification(
      Map<String, dynamic> data, String text) async {
    if (data['kind'] == 'team_chat') {
      await Api.sendTeamMessage(text);
      await clearChatNotifications(tournamentId: teamChatId, team: true);
      return;
    }
    final tournamentId = data['tournament_id'] as String?;
    if (tournamentId == null) return;
    final day = data['day'] as String?;
    final parsedDay = day == null ? null : Day.parse(day);
    await Api.sendMessage(tournamentId, parsedDay, text);
    await clearChatNotifications(tournamentId: tournamentId, day: parsedDay);
  }
```

(`teamChatId` import z místa, kde žije — viz Task 1 pozn. V background izolátu je metoda best-effort — try/catch uvnitř `clearChatNotifications` chytí případný neinicializovaný kanál.)

- [ ] **Step 3: Ověření**

Run: `flutter analyze && flutter test test/push/`
Expected: No issues, testy zelené. (Chování s pluginem se ověří manuálně při release — checklist ve specu.)

- [ ] **Step 4: Commit** — až spolu s Task 3 (teprve zavěšení do ChatScreen je viditelná změna).

---

### Task 3: ChatScreen — sweep v momentě přečtení

**Files:**
- Modify: `lib/features/chats/chat_screen.dart` (okolí `markRead`, ~ř. 409–417)

**Interfaces:**
- Consumes: `Push.clearChatNotifications` (Task 2). Identita: `widget.isTeam` → `team: true` + `tournamentId: widget.tournamentId` (sentinel); jinak `widget.tournamentId` + `widget.day`.

- [ ] **Step 1: Stavová pojistka proti sweep-u na každý build** — do `_ChatScreenState` přidej pole:

```dart
  /// Poslední zpráva, pro kterou už proběhl úklid lišty — sweep se pouští
  /// jen při změně, ne na každý build.
  DateTime? _notificationsClearedAt;
```

- [ ] **Step 2: Zavěs sweep vedle markRead** — stávající blok nahraď:

```dart
    // Everything rendered counts as read (also as new messages stream in
    // while the chat is open) — feeds the unread badges in the chat list.
    // The same moment reconciles the Android tray: this chat's
    // notifications are stale now (see Push.clearChatNotifications).
    if (messages.isNotEmpty) {
      final latest = messages.last.createdAt;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(chatReadsProvider.notifier).markRead(_chatKey, latest);
        if (_notificationsClearedAt != latest) {
          _notificationsClearedAt = latest;
          unawaited(Push.clearChatNotifications(
            tournamentId: widget.tournamentId,
            day: widget.day,
            team: widget.isTeam,
          ));
        }
      });
    }
```

Importy: `dart:async` (unawaited — zkontroluj, možná už je), `package:terminator/push/push.dart` → relativně `../../push/push.dart` (drž styl okolních importů).

- [ ] **Step 3: Ověření**

Run: `flutter analyze && flutter test`
Expected: No issues, celá suite zelená (v testech plugin chybí → sweep spadne do try/catch, nic nerozbije).

- [ ] **Step 4: Commit**

```bash
git add lib/push/push.dart lib/features/chats/chat_screen.dart
git commit -m "feat(push): přečtený chat si uklidí notifikace z lišty"
```

---

### Task 4: Otevřený chat notifikaci nekreslí

**Files:**
- Modify: `lib/push/push.dart` (`_openChat` + registrace + guard v `_showForeground`)
- Modify: `lib/features/chats/chat_screen.dart` (`initState`/`dispose`)

**Interfaces:**
- Produces: `Push.setOpenChat({required String tournamentId, Day? day, bool team = false})`, `Push.clearOpenChat({required String tournamentId, Day? day, bool team = false})` (clear jen když je registrovaný právě tento chat — chaty se umí navrstvit navigatorem).

- [ ] **Step 1: Registrace v `Push`**

```dart
  /// Chat právě na obrazovce (ChatScreen se hlásí v initState/dispose) —
  /// jeho příchozí pushe se nekreslí: markRead je vzápětí označí přečtené
  /// a sweep by notifikaci jen bliknul. Vrstvené chaty: clear maže jen
  /// vlastní registraci.
  static ({String tournamentId, Day? day, bool team})? _openChat;

  static void setOpenChat(
          {required String tournamentId, Day? day, bool team = false}) =>
      _openChat = (tournamentId: tournamentId, day: day, team: team);

  static void clearOpenChat(
      {required String tournamentId, Day? day, bool team = false}) {
    if (_openChat == (tournamentId: tournamentId, day: day, team: team)) {
      _openChat = null;
    }
  }
```

- [ ] **Step 2: Guard ve `_showForeground`** — na začátek, před stavbu `data`:

```dart
  static Future<void> _showForeground(RemoteMessage message) async {
    // The chat the user is looking at doesn't notify — markRead marks it
    // read the moment the message renders anyway.
    if (_openChat case final open?) {
      if (chatDataMatches(message.data,
          tournamentId: open.tournamentId, day: open.day, team: open.team)) {
        return;
      }
    }
    ...původní tělo beze změny...
  }
```

- [ ] **Step 3: ChatScreen `initState`/`dispose`**

V `initState` (za stávající obsah):

```dart
    Push.setOpenChat(
        tournamentId: widget.tournamentId,
        day: widget.day,
        team: widget.isTeam);
```

V `dispose` (před `super.dispose()`):

```dart
    Push.clearOpenChat(
        tournamentId: widget.tournamentId,
        day: widget.day,
        team: widget.isTeam);
```

- [ ] **Step 4: Ověření + commit**

Run: `flutter analyze && flutter test`
Expected: No issues, suite zelená.

```bash
git add lib/push/push.dart lib/features/chats/chat_screen.dart
git commit -m "feat(push): otevřený chat nekreslí vlastní notifikace"
```

---

### Task 5: Server — tag na chat + poznámka v NOTIFICATIONS.md

**Files:**
- Modify: `supabase/functions/notify/index.ts` (case `messages` ~ř. 899–915, case `team_messages` ~ř. 925–936)
- Modify: `NOTIFICATIONS.md` (krátká poznámka k chat pushům)

**Interfaces:**
- Consumes: `sendToTokens(tokens, title, body, data, tag?, dataOnly)` — tag je 5. parametr, dnes `undefined`.
- Produces: tag `chat:<tournamentId>` / `chat:<tournamentId>:<day>` / `team_chat` (formát ze specu).

- [ ] **Step 1: case `messages`** — nahraď `undefined` tagem:

```ts
        {
          kind: "chat",
          tournament_id: tournamentId,
          ...(day === null ? {} : { day }),
        },
        // Jedna položka lišty na chat: stejný tag = nová zpráva nahradí
        // starou (klient pak maže podle payloadu kind/tournament_id/day —
        // lib/push/chat_notification_match.dart drž v syncu s data výše).
        day === null ? `chat:${tournamentId}` : `chat:${tournamentId}:${day}`,
        true, // data-only → the app draws it with the inline reply
```

- [ ] **Step 2: case `team_messages`** — nahraď `undefined`:

```ts
        { kind: "team_chat" },
        // Jeden tým na člověka → stačí konstantní tag (viz messages výše).
        "team_chat",
        true, // data-only → the app draws it with the inline reply
```

- [ ] **Step 3: NOTIFICATIONS.md** — do sekce „1. Okamžité (webhook)" za odstavec o přidávání doplň:

```markdown
Chatové pushe navíc nesou tag chatu (`chat:<tournament>[:<den>]`,
`team_chat`): v liště je tak na chat nejvýš jedna položka a klient je
v momentě přečtení maže podle payloadu
(lib/push/chat_notification_match.dart — kontrakt kind + tournament_id +
day drž v syncu).
```

- [ ] **Step 4: Typecheck (je-li deno k dispozici) + commit**

Run: `deno check supabase/functions/notify/index.ts || echo "deno check nedostupný — přeskočeno"`
Expected: bez chyb (nebo přeskočeno).

```bash
git add supabase/functions/notify/index.ts NOTIFICATIONS.md
git commit -m "feat(notify): chat pushe s tagem — jedna položka lišty na chat"
```

---

### Task 6: Závěrečné ověření

- [ ] **Step 1:** `flutter analyze` → No issues found.
- [ ] **Step 2:** `flutter test` → All tests passed (celá suite, ~190+).
- [ ] **Step 3:** Zkontroluj `git status` — čistý strom, žádný zapomenutý soubor.
- [ ] **Step 4:** Připomeň manuální release checklist ze specu (5 bodů) — provede se při příštím vydání buildu; deploy EF `notify` jen na pokyn.
