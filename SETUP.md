# Termínátor — Setup (one-time, ~15 minutes of clicking)

The app is fully built; it just needs its free backend accounts. Steps 1–4 get
the team scheduling. Steps 5–7 add push notifications. Step 8 keeps the free
database awake. Step 9 builds the APK for the team.

## 1. Supabase project (free, no credit card)

1. Sign up at <https://supabase.com> → **New project** (region: Central EU).
2. From **Project Settings → API** note:
   - **Project URL** → your `SUPABASE_URL`
   - **anon / publishable key** → your `SUPABASE_ANON_KEY`

## 2. Database schema

1. Dashboard → **SQL Editor** → paste and **Run** each file from
   [`supabase/migrations/`](supabase/migrations/) **in order**
   (`0001_init.sql`, then `0002_notification_prefs.sql`).
2. Set the team invite code (pick your own secret word):

   ```sql
   insert into team_settings (invite_code) values ('KUZELKY2026');
   ```

## 3. Auth (magic links)

Dashboard → **Authentication → URL Configuration** → **Redirect URLs** → add:

```
cz.kuzelky.terminator://login-callback
```

That's all — magic-link e-mail is enabled by default. Supabase's built-in
e-mail sending is rate-limited (fine for a few sign-ins a day). When you
onboard the whole team in one evening, plug in a free SMTP first
(**Authentication → SMTP**, e.g. Brevo — 300 mails/day free), or spread
sign-ins out.

## 4. Run the app

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOURREF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

The **first person to sign in and enter the invite code becomes the founder**
(auto-approved). Everyone after that waits for a one-tap approval in the
**Tým** tab.

## 5. Firebase project (push notifications — can be done later)

1. <https://console.firebase.google.com> → **Add project** (no Analytics needed).
2. **Project settings → General → Your apps → Add app → Android**, package
   name `cz.kuzelky.terminator`. You do **not** need google-services.json —
   the app initializes Firebase from dart-defines. Note these four values:
   - `FIREBASE_API_KEY` (Web API Key on the General tab)
   - `FIREBASE_APP_ID` (the Android app's App ID, `1:...:android:...`)
   - `FIREBASE_SENDER_ID` (Cloud Messaging → Sender ID)
   - `FIREBASE_PROJECT_ID`
3. **Project settings → Service accounts → Generate new private key** →
   download the JSON (used by the Edge Function below).

Add the four values as extra `--dart-define`s when building/running.

## 6. Deploy the notify Edge Function

Install the [Supabase CLI](https://supabase.com/docs/guides/cli), then:

```bash
supabase login
supabase link --project-ref YOURREF        # run inside this repo
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat path/to/service-account.json)"
supabase functions deploy notify
```

## 7. Database webhooks (what triggers the pushes)

Dashboard → **Database → Webhooks** → create **five** webhooks, all pointing
to the **notify** Edge Function (type: *Supabase Edge Function*):

| Name                | Table        | Events         |
|---------------------|--------------|----------------|
| notify-members      | profiles     | INSERT         |
| notify-tournaments  | tournaments  | INSERT         |
| notify-orders       | orders       | INSERT, UPDATE |
| notify-messages     | messages     | INSERT         |
| notify-availability | availability | INSERT         |

That gives you: new-member approval, new tournament, proposal + ordered +
cancelled, chat messages (mute-aware), and the "slot reached min players"
nudge — all the v1 notifications.

## 8. Keep-alive (free tier pauses after 7 idle days)

Push this repo to GitHub, then in the repo settings → **Secrets and
variables → Actions** add `SUPABASE_URL` and `SUPABASE_ANON_KEY`. The
included workflow [`.github/workflows/keepalive.yml`](.github/workflows/keepalive.yml)
pings the database twice a week so the project never pauses.

## 9. Build the APK for the team

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_SENDER_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=...
```

Share `build/app/outputs/flutter-apk/app-release.apk` with the team
(e-mail / drive link). Android will ask to allow installing from unknown
sources — that's expected for a direct APK.

iOS: the codebase is iOS-ready (deep link + push code included); building and
publishing needs an Apple Developer account — deferred by plan.
