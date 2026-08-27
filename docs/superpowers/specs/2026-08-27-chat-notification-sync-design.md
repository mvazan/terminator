# Chat notifikace v sync s přečtením

Datum: 2026-08-27 · Stav: schváleno (varianta A)

## Problém

Chatové pushe se v Android liště vrší a nikdy se nesrovnají s tím, co si
člověk reálně přečetl:

1. Přijde víc notifikací z jednoho chatu; ťuknutí na nejnovější smaže jen
   ji, starší zůstávají — přestože otevřený chat člověk dočetl celý.
2. Zprávy ze dvou chatů: přepnutí z chatu do chatu uvnitř appky notifikaci
   druhého chatu nesmaže.
3. Vstup do appky ikonou (ne notifikací) a přečtení chatu notifikaci
   nesmaže.

Příčiny (ověřeno v kódu): server chat pushům neposílá `tag`
(supabase/functions/notify/index.ts, case `messages` / `team_messages`),
takže každá zpráva je nová položka v liště; a klient nikde nevolá
`cancel()` — lišta se nikdy nesrovná s read-state, který appka přitom
přesně zná (`markRead` v lib/features/chats/chat_screen.dart živí unread
badge v seznamu chatů).

## Řešení (varianta A)

### 1. Server: tag na chat

V EF `notify` dostanou chatové pushe tag identifikující chat:

| chat            | tag                              |
|-----------------|----------------------------------|
| turnajový chat  | `chat:<tournamentId>`            |
| denní chat      | `chat:<tournamentId>:<YYYY-MM-DD>` |
| týmový chat     | `team_chat`                      |

Stejný tag = nová zpráva NAHRADÍ starou položku v liště (chování, které už
používá threshold push): na chat je v liště vždy nejvýš jedna notifikace
s poslední zprávou. `sendToTokens` tag už umí a klient (`_showFromData`)
ho už čte — funguje hned po deployi EF i pro staré buildy, bez min_build.
Týmový chat nepotřebuje team_id v tagu: člověk je vždy jen v jednom týmu.

Tag konstruuje jen server (klient ho pouze zrcadlí při kreslení a maže
podle payloadu, ne tagu) — smluvený je payload kontrakt kind +
tournament_id + day; komentáře "keep in sync" v EF a v matcheru na sebe
vzájemně odkazují (stejný vzor jako channel ids).

### 2. Klient: úklid lišty při přečtení

Nová metoda `Push.clearChatNotifications({tournamentId, day, team})`:
přes `getActiveNotifications()` (Android implementace pluginu) projde
aktivní notifikace a zruší (`cancel(id, tag)`) ty, jejichž **payload**
patří danému chatu. Match podle payloadu, ne tagu: chat pushe se renderují
lokálně (data-only, min_build 58 ≥ 45), payload s `kind` +
`tournament_id` + `day` je u notifikace vždy — úklid tak srovná i
notifikace doručené před nasazením tagů.

Matching je čistá funkce (payload JSON + identita chatu → bool) v
`lib/push/`, testovaná unit testy; sweep okolo ní je tenký.

Zavěšení: v ChatScreen vedle existujícího `markRead` — při otevření chatu
a pak jen když se změní `messages.last.createdAt` (žádný sweep na každý
build). Tím jsou pokryté všechny tři scénáře: starší notifikace téhož
chatu, přepnutí mezi chaty, vstup ikonou.

### 3. Klient: otevřený chat notifikaci nekreslí

ChatScreen se při init/dispose registruje u `Push` jako aktuálně otevřený
chat; `_showForeground` push pro tento chat zahodí (dnes by jen blikl a
sweep by ho hned smazal). Jiné obrazovky appky chování nemění.

### 4. Klient: inline „Odpovědět" uklidí chat

`sendReplyFromNotification` po úspěšném odeslání zavolá stejný sweep pro
daný chat — kdo odpovídá, kontext četl. Funguje i v background izolátu
(plugin tam už dnes kreslí notifikace, `getActiveNotifications` je tamtéž
dostupné).

## Mimo scope

- iOS: sweep i potlačení jdou přes Android implementaci pluginu, na iOS
  no-op. Co by iOS vydání potřebovalo, eviduje IOS.md (kořen repa).
- Čtení na jiném zařízení: read-state je lokální, tým má telefon na
  člověka.
- Engine 0025, prefs loud/silent, mute, membership denních chatů a
  routing ťuknutí se nemění.

## Testy

- Unit: matching funkce — turnajový/denní/týmový chat, cizí chat, jiný
  kind, chybějící/rozbitý payload JSON.
- Manuální checklist při release:
  1. Dvě zprávy z jednoho chatu → v liště jedna položka (poslední zpráva).
  2. Otevření chatu ikonou appky → položka zmizí.
  3. Přepnutí do druhého chatu uvnitř appky → jeho položka zmizí.
  4. Inline odpověď z notifikace → položky chatu zmizí.
  5. Zpráva do otevřeného chatu → žádná notifikace.

## Dotčené soubory

- `supabase/functions/notify/index.ts` — tagy (case `messages`,
  `team_messages`).
- `lib/push/push.dart` — `clearChatNotifications`, registrace otevřeného
  chatu, potlačení ve `_showForeground`, sweep po reply.
- `lib/push/chat_notification_match.dart` (nový) — čistá matching funkce.
- `lib/features/chats/chat_screen.dart` — volání sweepu u `markRead`,
  registrace otevřeného chatu.
- `test/push/chat_notification_match_test.dart` (nový).
- `IOS.md` (nový) — evidence iOS specifik.

## Nasazení

Deploy EF `notify` zlepší lištu okamžitě i starým buildům (tag =
nahrazování). Klientská část (sweep, potlačení, reply úklid) vyjde s
příštím buildem; min_build netřeba.
