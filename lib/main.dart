import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'core/app_theme.dart';
import 'core/offline_banner.dart';
import 'core/text_size.dart';
import 'core/theme_choice.dart';
import 'core/ui.dart';
import 'data/local_prefs.dart';
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

class TerminatorApp extends ConsumerWidget {
  const TerminatorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Vzhled z Nastavení: Termínátor = podle systému s běžným kontrastem
    // (dosavadní chování), Světlý/Tmavý vynutí jas s maximálním kontrastem.
    final plan = themePlanFor(ref.watch(themeChoiceProvider));
    final textSize = ref.watch(textSizeProvider);
    return MaterialApp(
      title: 'Termínátor',
      navigatorKey: Push.navigatorKey,
      debugShowCheckedModeBanner: false,
      // Wraps the Navigator: the chosen text size on every screen, plus the
      // offline banner (only with a backend — the provider touches
      // Supabase.instance).
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
              textScaler: AppTextScaler(mq.textScaler, textSize)),
          child: AppConfig.hasSupabase
              ? OfflineBanner(child: child!)
              : child!,
        );
      },
      locale: const Locale('cs'),
      supportedLocales: const [Locale('cs'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: appTheme(Brightness.light, plan.contrastLevel),
      darkTheme: appTheme(Brightness.dark, plan.contrastLevel),
      themeMode: plan.mode,
      home: AppConfig.hasSupabase ? const AuthGate() : const _NotConfigured(),
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
