import 'package:flutter/material.dart';

import '../../core/ui.dart';

/// Why the user is parked in front of the app.
enum WaitingReason {
  /// Their profile awaits a member's approval.
  memberApproval,

  /// Their (newly founded) team awaits the app owner's approval.
  teamApproval,
}

/// Shown while the profile — or the whole team — is pending. The relevant
/// stream flips on approval and AuthGate lets the user in automatically.
class WaitingScreen extends StatelessWidget {
  const WaitingScreen({super.key, this.reason = WaitingReason.memberApproval});

  final WaitingReason reason;

  @override
  Widget build(BuildContext context) {
    final member = reason == WaitingReason.memberApproval;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🕰️', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(
                member ? 'Čekáš na schválení' : 'Tým čeká na schválení',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                member
                    ? 'Partě přišlo upozornění, že ses přidal(a).\n'
                        'Jakmile tě někdo z týmu schválí, pustíme tě dál — '
                        'obrazovka se přepne sama.'
                    : 'Nový tým musí schválit správce aplikace — dostal '
                        'upozornění.\nJakmile tým schválí, pustíme tě dál — '
                        'obrazovka se přepne sama.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
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
