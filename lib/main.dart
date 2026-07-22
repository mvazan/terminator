import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'core/offline_banner.dart';
import 'core/ui.dart';
import 'features/auth/auth_gate.dart';
import 'push/push.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sentry (optional): with a DSN it wraps startup so uncaught Flutter/Dart
  // errors are reported; without one it's a no-op and the app starts normally.
  if (AppConfig.hasSentry) {
    await SentryFlutter.init(
      (options) {
        options.dsn = AppConfig.sentryDsn;
        options.sendDefaultPii = false; // no IP/user data beyond the error
        // Drop connectivity noise: GoTrue's background token-refresh timer and
        // the realtime channels throw uncaught when the device is offline,
        // which would otherwise land as fatal crashes. Offline is the user's
        // network situation, not a defect (same stance as tryAction).
        options.beforeSend = (event, hint) {
          final err = event.throwable;
          if (err != null && isOfflineError(err)) return null;
          // Expired sign-in links are user timing, not a defect — the
          // onError hook below shows the friendly dialog.
          if (err != null && _isExpiredAuthLink(err)) return null;
          return event;
        };
      },
      appRunner: _bootstrap,
    );
  } else {
    await _bootstrap();
  }
}

/// A tapped sign-in e-mail link that's stale: GoTrue's deeplink handler
/// throws this uncaught, the user gets silence. Both fields seen in the
/// wild: statusCode "otp_expired", code "access_denied".
bool _isExpiredAuthLink(Object error) =>
    error is AuthException &&
    (error.statusCode == 'otp_expired' ||
        error.code == 'otp_expired' ||
        error.message.toLowerCase().contains('invalid or has expired'));

/// Explains an expired link instead of doing nothing — the user is on the
/// sign-in screen anyway; tell them why and what to do.
void _showExpiredLinkNotice() {
  Future<void>.delayed(const Duration(milliseconds: 300), () {
    final context = Push.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Odkaz už neplatí'),
        content: const Text(
            'Přihlašovací odkaz z e-mailu mezitím vypršel. Zadej e-mail '
            'znovu a pošleme ti čerstvý kód.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Rozumím'),
          ),
        ],
      ),
    );
  });
}

/// Backend init + runApp — shared so Sentry's appRunner and the no-Sentry path
/// run exactly the same startup.
Future<void> _bootstrap() async {
  if (AppConfig.hasSupabase) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    await Push.init();

    // Catch the expired-sign-in-link throw from the deeplink handler before
    // it lands as an unhandled fatal; everything else chains on (Sentry).
    final previousOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      if (_isExpiredAuthLink(error)) {
        _showExpiredLinkNotice();
        return true;
      }
      return previousOnError?.call(error, stack) ?? false;
    };
  }

  runApp(const ProviderScope(child: TerminatorApp()));
}

class TerminatorApp extends StatelessWidget {
  const TerminatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Termínátor',
      navigatorKey: Push.navigatorKey,
      debugShowCheckedModeBanner: false,
      // Offline banner over EVERY screen (wraps the Navigator). Only when a
      // backend is configured — the provider touches Supabase.instance.
      builder: AppConfig.hasSupabase
          ? (context, child) => OfflineBanner(child: child!)
          : null,
      locale: const Locale('cs'),
      supportedLocales: const [Locale('cs'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: AppConfig.hasSupabase ? const AuthGate() : const _NotConfigured(),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF8E2430), // kuželky bordeaux
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainerLowest,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: scheme.surfaceContainer,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.4),
      ),
    );
  }
}

/// Shown when the app was built without --dart-define backend credentials.
class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Termínátor 🎳\n\n'
            'Aplikace není nakonfigurovaná.\n\n'
            'Sestav ji s přístupem k backendu:\n'
            'flutter run --dart-define=SUPABASE_URL=... '
            '--dart-define=SUPABASE_ANON_KEY=...\n\n'
            'Podrobnosti najdeš v SETUP.md.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
