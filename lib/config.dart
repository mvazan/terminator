/// Build-time configuration. Values come from --dart-define (see SETUP.md):
///
///   flutter run \
///     --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJ... \
///     --dart-define=FIREBASE_API_KEY=... \
///     --dart-define=FIREBASE_APP_ID=... \
///     --dart-define=FIREBASE_SENDER_ID=... \
///     --dart-define=FIREBASE_PROJECT_ID=...
///
/// Supabase values are required; Firebase values are optional — without them
/// the app runs fine, just without push notifications.
library;

class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseProjectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID');

  /// Sentry crash/error reporting DSN. Optional — without it Sentry stays off
  /// (debug builds run clean). The DSN is a public client key, safe to bake in.
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// Deep link the magic-link e-mail redirects back to (registered in
  /// AndroidManifest and in the Supabase dashboard's redirect URLs).
  static const authRedirectUrl = 'cz.kuzelky.terminator://login-callback';

  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasFirebase =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;

  static bool get hasSentry => sentryDsn.isNotEmpty;
}
