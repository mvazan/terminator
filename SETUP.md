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

1. Dashboard → **SQL Editor** → paste and **Run**
   [`supabase/migrations/0001_schema.sql`](supabase/migrations/0001_schema.sql)
   (the complete schema, including the webhook triggers that drive push
   notifications — no dashboard webhook clicking needed).
2. Set the team invite code (pick your own secret word):

   ```sql
   insert into team_settings (invite_code) values ('KUZELKY2026');
   ```

## 3. Auth (magic links)

Dashboard → **Authentication → URL Configuration** → **Redirect URLs** → add:

```
cz.kuzelky.terminator://login-callback
```

Magic-link e-mail is enabled by default, but Supabase's built-in sending is
heavily rate-limited and English-only. The production setup uses **Gmail
SMTP**: in your Google account enable 2-Step Verification, create an App
Password (<https://myaccount.google.com/apppasswords>), then in Supabase →
**Authentication → SMTP** set host `smtp.gmail.com`, port `587`, user = your
Gmail address, password = the app password, sender name `Termínátor`.
Gmail allows ~500 mails/day — plenty. With custom SMTP active you can also
localize the e-mail templates (**Authentication → Email Templates**).
Caveat when configuring via the Management API: set SMTP first, templates in
a separate second request — a combined request is silently dropped.

Keep `{{ .Token }}` in the magic-link and confirmation templates: some mail
apps (e.g. Seznam's in-app browser) drop the `?code=` query when opening the
app from the link, so the login screen offers "Zadat kód z e-mailu" as a
fallback — the code in the e-mail is what makes it work.

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

## 7. Webhook secret (what authenticates the pushes)

The webhook triggers live in the schema (step 2) and send an
`x-webhook-secret` header; the notify function checks it against its
`WEBHOOK_SECRET` secret. Generate and set it once:

```bash
supabase secrets set WEBHOOK_SECRET=<the secret embedded in 0001_schema.sql>
```

(The secret is the string in the `notify_webhook()` function definition —
keep the two in sync.) That gives you all the v1 notifications: new-member
approval, new tournament, proposal + ordered + cancelled, chat messages
(mute-aware), and the "slot reached min players" nudge.

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
