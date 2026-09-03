import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import '../shell.dart';
import 'join_screen.dart';
import 'login_screen.dart';
import 'update_screen.dart';
import 'waiting_screen.dart';

/// Routes by auth/profile state:
/// too-old build -> update, no session -> login, no profile -> invite code,
/// pending -> waiting, approved -> the app. All transitions are live
/// (streams).
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  /// Coming back to the foreground re-reads min_build: the Realtime stream
  /// is the fast path, this is the belt for a socket that died meanwhile.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onResume: () => ref.invalidate(minBuildProvider),
  );

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Force-update gate: when the backend says this build is too old,
    // block everything with the update screen — live, so a running app
    // locks within seconds of a bump. Unknown (offline, older backend)
    // never blocks.
    if (ref.watch(updateRequiredProvider)) {
      return const UpdateScreen();
    }

    final auth = ref.watch(authStateProvider);
    final session = auth.value?.session ??
        Supabase.instance.client.auth.currentSession;

    if (auth.isLoading && session == null) {
      return const _Splash();
    }
    if (session == null) {
      return const LoginScreen();
    }

    final profile = ref.watch(myProfileProvider);
    return profile.when(
      loading: () => const _Splash(),
      error: (e, _) => _ErrorScreen(error: '$e'),
      data: (p) {
        if (p == null) return const JoinScreen();
        if (p.status == ProfileStatus.pending) return const WaitingScreen();
        // Approved member of a not-yet-approved team (fresh founder): wait
        // for the superadmin. Flips live via the teams stream.
        final team = ref.watch(myTeamProvider);
        if (team != null && !team.approved) {
          return const WaitingScreen(reason: WaitingReason.teamApproval);
        }
        return const MainShell();
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.asset('assets/icon/login_logo.png',
              width: 96, height: 96),
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Něco se pokazilo.'),
              const SizedBox(height: 8),
              Text(error, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => confirmSignOut(context),
                child: const Text('Odhlásit se'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
