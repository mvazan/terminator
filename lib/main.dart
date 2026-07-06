import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'features/auth/auth_gate.dart';
import 'push/push.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.hasSupabase) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    await Push.init();
  }

  runApp(const ProviderScope(child: TerminatorApp()));
}

class TerminatorApp extends StatelessWidget {
  const TerminatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Termínátor',
      debugShowCheckedModeBanner: false,
      locale: const Locale('cs'),
      supportedLocales: const [Locale('cs'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8E2430), // kuželky bordeaux
        ),
        useMaterial3: true,
      ),
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
