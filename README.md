# Termínátor 🎳

*Hasta la vista, prázdná dráha.*

Tournament scheduler for a Czech nine-pin bowling (kuželky) team: members tick
which start slots they can make, the app shows a popularity heatmap, the team
votes on a proposal (Beru / Nemůžu / Radši jiný den), someone orders the
starts with the organizer and records how many places were taken, latecomers
join while places are free, and every tournament and played day has a chat
that archives itself.

- **Design & implementation plan:** `~/Home/termínátor.md`
- **Czech intro for the team / focus group:** `~/Home/terminator-predstaveni.md`
- **Backend setup guide (one-time):** [SETUP.md](SETUP.md)

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
                        # heatmap + best picks, timeline weeks, places math,
                        # chat lock policy
  data/providers.dart   # Riverpod streams over Supabase + all write actions
  features/             # auth gate, my starts, tournaments (heatmap, timeline,
                        # proposals, orders, rosters), chats, team
  push/push.dart        # FCM client side (no-op without Firebase dart-defines)
supabase/
  migrations/0001_init.sql   # schema, RLS, join_team/approve_member RPCs
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
