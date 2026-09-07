import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:terminator/data/providers.dart';
import 'package:terminator/features/auth/auth_gate.dart';
import 'package:terminator/features/auth/login_screen.dart';
import 'package:terminator/features/auth/update_screen.dart';

/// Keeps the PKCE verifier in memory — the default shared_preferences
/// storage has no platform channel under flutter_test.
class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final _items = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async =>
      _items[key] = value;

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // The gate reads the client's current session; a mock-backed client with
    // no session and no URL detection keeps the test offline.
    await Supabase.initialize(
      url: 'http://localhost',
      publishableKey: 'anon',
      httpClient: MockClient((_) async => http.Response('[]', 200)),
      authOptions: FlutterAuthClientOptions(
        detectSessionInUri: false,
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryAsyncStorage(),
      ),
    );
  });

  Widget app({required bool updateRequired}) {
    return ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) =>
            Stream.value(const AuthState(AuthChangeEvent.initialSession, null))),
        updateRequiredProvider.overrideWithValue(updateRequired),
      ],
      child: const MaterialApp(home: AuthGate()),
    );
  }

  testWidgets('a too-old build sees the update screen even before signing in',
      (tester) async {
    await tester.pumpWidget(app(updateRequired: true));
    await tester.pump();

    expect(find.byType(UpdateScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('a current build gets the login screen', (tester) async {
    await tester.pumpWidget(app(updateRequired: false));
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(UpdateScreen), findsNothing);
  });
}
