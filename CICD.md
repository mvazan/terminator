# Termínátor — CI/CD guide

## The picture

```
push / PR ──────────────► CI (ci.yml): flutter analyze + flutter test
push to main
  touching supabase/** ─► deploy-backend.yml: supabase db push
                                              supabase functions deploy notify
push tag v* ────────────► release.yml: signed release APK with production
                          backend baked in → GitHub Releases page
weekly cron ────────────► keepalive.yml: pings Supabase so the free tier
                          never pauses
```

**Where is Firebase in the pipeline? Nowhere — by design.** This stack uses
Firebase only for FCM delivery. There is nothing to deploy to it: the app gets
the four `FIREBASE_*` values baked in at build time, and the Edge Function
reads the service-account JSON from a Supabase secret (SETUP.md step 6, set
once). Only if you someday rotate that key do you re-run
`supabase secrets set FIREBASE_SERVICE_ACCOUNT=...`.

## One-time setup

### 1. Push the repo to GitHub

```bash
cd ~/Home/terminator
gh repo create terminator --private --source=. --push
# or: create an empty repo on github.com, then
# git remote add origin git@github.com:YOU/terminator.git && git push -u origin main
```

### 2. Create the release signing key (once, keep forever)

Android requires every update to be signed with the same key — if you lose
it, the team must uninstall/reinstall. Generate it locally and back it up:

```bash
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias terminator
base64 -i upload-keystore.jks | pbcopy   # copies the base64 for the secret
```

Do **not** commit the .jks (it's gitignored). Store it somewhere safe.

### 3. Get the Supabase deploy credentials

- **Access token**: <https://supabase.com/dashboard/account/tokens> →
  Generate new token.
- **Project ref**: the `xyz` part of `https://xyz.supabase.co`
  (Project Settings → General).
- **DB password**: the database password you chose at project creation
  (Project Settings → Database → reset it if forgotten).

### 4. Add the GitHub Actions secrets

Repo → Settings → Secrets and variables → Actions → New repository secret:

| Secret | Used by | Value |
|---|---|---|
| `SUPABASE_URL` | release, keepalive | `https://xyz.supabase.co` |
| `SUPABASE_ANON_KEY` | release, keepalive | anon/publishable key |
| `SUPABASE_ACCESS_TOKEN` | deploy-backend | personal access token |
| `SUPABASE_PROJECT_REF` | deploy-backend | `xyz` |
| `SUPABASE_DB_PASSWORD` | deploy-backend | database password |
| `FIREBASE_API_KEY` | release | Firebase Web API key |
| `FIREBASE_APP_ID` | release | Android app id `1:...:android:...` |
| `FIREBASE_SENDER_ID` | release | Cloud Messaging sender id |
| `FIREBASE_PROJECT_ID` | release | Firebase project id |
| `ANDROID_KEYSTORE_BASE64` | release | output of the base64 command above |
| `ANDROID_KEYSTORE_PASSWORD` | release | keystore password |
| `ANDROID_KEY_ALIAS` | release | `terminator` |
| `ANDROID_KEY_PASSWORD` | release | key password (often = store password) |

The `FIREBASE_*` secrets may be empty at first — the app then builds without
push notifications and everything else works.

### 5. If you already applied migrations by hand

If you ran `0001_init.sql` / `0002_notification_prefs.sql` through the SQL
editor (SETUP.md), tell the CLI they're already applied — otherwise the first
`supabase db push` tries to run them again:

```bash
supabase link --project-ref xyz
supabase migration repair --status applied 0001 0002
```

From then on, **new migrations go through git**: add
`supabase/migrations/0003_whatever.sql`, merge to main, and the pipeline
applies it.

## Everyday flow

- **Change code** → push / open PR → CI runs analyzer + tests.
- **Change schema or the notify function** → merge to main → backend deploys
  itself (path-filtered, runs only when `supabase/**` changed).
- **Ship to the team**:

  ```bash
  # 1. bump version in pubspec.yaml, e.g. 1.1.0+3  (versionCode must grow)
  git commit -am "Bump version to 1.1.0"
  git tag v1.1.0 && git push origin main v1.1.0
  ```

  A few minutes later the signed `terminator-v1.1.0.apk` is on the repo's
  **Releases** page — share that link in the team chat. Installing over the
  old version works (same signing key).

## Optional upgrade: Firebase App Distribution

If sharing the Releases link ever feels clumsy, Firebase **App Distribution**
(free) can push each build to teammates by e-mail with an "update available"
flow. Add one step to release.yml after the build:

```yaml
- uses: wzieba/Firebase-Distribution-Github-Action@v1
  with:
    appId: ${{ secrets.FIREBASE_APP_ID }}
    serviceCredentialsFileContent: ${{ secrets.FIREBASE_SERVICE_ACCOUNT }}
    groups: team
    file: build/app/outputs/flutter-apk/app-release.apk
```

Not enabled by default — GitHub Releases is simpler and has no extra accounts.
