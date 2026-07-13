import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
/// no session -> login, no profile -> invite code, pending -> waiting,
/// approved -> the app. All transitions are live (streams).
final _buildNumberProvider = FutureProvider<int?>((_) async =>
    int.tryParse((await PackageInfo.fromPlatform()).buildNumber));

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Force-update gate: when the backend says this build is too old,
    // block everything with the update screen. Unknown (offline, older
    // backend) never blocks.
    final minBuild = ref.watch(minBuildProvider).value;
    final build = ref.watch(_buildNumberProvider).value;
    if (minBuild != null && build != null && build < minBuild) {
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
