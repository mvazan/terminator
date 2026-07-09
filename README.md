# Termínátor 🎳

*Hasta la vista, prázdná dráha.*

Tournament scheduler for a Czech nine-pin bowling (kuželky) team: members tick
which start slots they can make, the app shows a popularity heatmap, someone
records an order (which starts and how many lanes) with the organizer,
latecomers join while places are free, and every tournament and played day has
a chat that archives itself. Tournaments pick a saved venue (its lane count
caps the order); the app can navigate to the venue and, for known organizer
sites, scrape start times and lane occupancy.

- **User guide (Czech, how to use the app):** [terminator-navod.md](terminator-navod.md)
- **Czech intro for the team / focus group:** `~/Home/terminator-predstaveni.md`
- **Design & implementation plan:** `~/Home/termínátor.md`
- **Backend setup guide (one-time):** [SETUP.md](SETUP.md)
- **CI/CD guide (GitHub Actions → Supabase, APK releases):** [CICD.md](CICD.md)

## Stack

| Piece      | Choice                                                        |
|------------|---------------------------------------------------------------|
| App        | Flutter (Android APK first; iOS-ready, published later)      |
| Backend    | Supabase free tier — Postgres + RLS, magic-link auth, Realtime |
| Push       | FCM HTTP v1, sent by the `notify` Supabase Edge Function     |
| State      | Riverpod; whole-table Realtime streams filtered client-side (fine at ~20 users) |

## Layout

```
lib/
  config.dart           # --dart-define backend credentials
  domain/               # pure Dart, unit-tested: models, slot generation,
                        # heatmap + best picks, timeline weeks, lanes/places
                        # math, chat lock policy
  data/providers.dart   # Riverpod streams over Supabase + all write actions
  features/             # auth gate, my starts, tournaments (heatmap, timeline,
                        # orders, rosters), venues, chats, team, hidden manage
  push/push.dart        # FCM client side (no-op without Firebase dart-defines)
  scrape/               # per-organizer scrapers (mkware, turnajekuzelky.cz)
supabase/
  migrations/0001_schema.sql # single squashed baseline: schema, RLS,
                             # join_team/approve_member/set_member_hidden RPCs,
                             # notify webhook triggers
  functions/notify/          # webhook-driven push notifications
```

## Development

```bash
flutter test                          # domain + widget tests
flutter analyze
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

Without the dart-defines the app builds and shows a "not configured" screen;
push is disabled unless the `FIREBASE_*` defines are present (see SETUP.md).
