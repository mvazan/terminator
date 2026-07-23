# Notifikace — jak fungují a jak přidat další

Dvě cesty, jak z události vznikne push. Než přidáš novou notifikaci,
rozhodni, kterou cestou má jít — a NEVYMÝŠLEJ třetí.

## 1. Okamžité (webhook)

Událost → DB trigger `notify_webhook()` → EF `notify` → FCM. Pro události,
kde okamžitost dává smysl a spam nehrozí: chat zprávy, nový turnaj, nový
člen, zrušení objednávky.

Přidání: webhook trigger na tabulku (vzor v 0001/0012) + `case` v
`supabase/functions/notify/index.ts`.

## 2. Odložené (engine `notification_jobs`, 0025)

Pro všechno, kde hrozí zahlcení, uklik nebo ping-pong: událost NEposílá
push, ale zařadí JOB, který dozraje za pár minut. Tři pravidla dělají
veškerou práci:

1. **Debounce** — stejný `dedupe_key` se upsertuje (posune `run_at`),
   nikdy nevznikne duplicitní job. Klikání sem-tam = pořád jeden job.
2. **Undo** — opačná akce čekající job SMAŽE
   (`dequeue_notification(key)` vrací, jestli nějaký čekal). Uklik
   vyřešený do 3 minut = nula notifikací.
3. **Revalidace** — handler v EF si stav ověří až při odeslání. Zastaralý
   job nikdy nepošle nepravdu; při pochybnosti mlčí.

Infrastruktura (0025): tabulka `notification_jobs` (kind, dedupe_key
unique, payload jsonb, run_at) + `enqueue_notification()` /
`dequeue_notification()` (security definer — volatelné z triggerů) +
minutový pg_cron `notification-jobs` → EF `processJobs()`.

### Recept: nový odložený druh

1. **Producer** (migrace): DB trigger na událost →
   `enqueue_notification('muj_kind', 'muj_kind:<id>', payload)`.
   Klíč navrhni tak, aby opakování téže věci kolidovalo (debounce)
   a opačná akce ho uměla smazat (undo).
2. **Handler** (EF `notify/index.ts`): `case "muj_kind"` v `processJobs`
   — revaliduj stav (jednotka pravdy = DB v okamžiku odeslání), pak
   `sendToTokens(teamTokens(...))`. Pomocníci: `orderContext()`,
   `teamTokens(kind, exclude, teamId, memberIds)` — `memberIds` s jedním
   uživatelem = osobní push respektující notification_prefs.
3. Hotovo — cron i mazání jobů jsou společné.

### Co na enginu už běží

| kind               | producer                          | co dělá |
|--------------------|-----------------------------------|---------|
| `order_free_spots` | insert objednávky, delete rosteru | po 3 min: volná místa → push nepřiřazeným bez skrytého turnaje; plno → ticho |
| `assigned`         | roster insert cizí rukou          | po 3 min: „Hraješ …" dotyčnému; smazán roster deletem (undo) |
| `removed`          | roster delete cizí rukou          | po 3 min: „Už nehraješ …"; smazán roster insertem (undo) |

### Kandidáti na přesun (fáze 2)

- **threshold** (zaklikávání termínů) — dnes vlastní cooldown přes
  `slots.threshold_notified_at` + tag; přesun na engine
  (`threshold:<tournament_id>`, ~5 min debounce) sjednotí logiku.

## Zásady

- Notifikace jsou serverová věc — klient se kvůli nim NEbuildí, změny
  platí okamžitě pro všechny verze.
- Osobní > plošné: pokud jde adresáta určit, nikdy neposílej týmu.
- Plný stav = ticho (plná objednávka nikoho nezve).
- Respektuj `notification_prefs` (řeší `teamTokens`) a skryté turnaje
  (`hidersOf`).
