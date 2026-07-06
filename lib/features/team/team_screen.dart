import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import 'settings_screen.dart';

/// Team overview: my profile, pending approvals (anyone can approve — the
/// everyone-equal rule), member list, sign-out.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myProfileProvider).value;
    final members = ref.watch(membersProvider).value ?? const [];
    final pending = [for (final m in members) if (!m.isApproved) m];
    final approved = [for (final m in members) if (m.isApproved) m];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tým'),
        actions: [
          IconButton(
            tooltip: 'Nastavení',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (me != null)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(me.displayName),
              subtitle: const Text('To jsem já'),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Změnit jméno',
                onPressed: () => _editName(context, me),
              ),
            ),
          const Divider(),
          if (pending.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Čekají na schválení',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final m in pending)
              ListTile(
                leading: const Icon(Icons.hourglass_top),
                title: Text(m.displayName),
                trailing: FilledButton(
                  onPressed: () => tryAction(
                      context, () => Api.approveMember(m.id),
                      success: '${m.displayName} schválen(a). Vítej!'),
                  child: const Text('Schválit'),
                ),
              ),
            const Divider(),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Členové (${approved.length})',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          for (final m in approved)
            ListTile(
              dense: true,
              leading: const Icon(Icons.person_outline),
              title: Text(m.displayName),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Odhlásit se'),
            onTap: () => Api.signOut(),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Termínátor 🎳 — Hasta la vista, prázdná dráha.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editName(BuildContext context, Profile me) async {
    final controller = TextEditingController(text: me.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tvoje jméno'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Zrušit')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Uložit'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      await tryAction(context, () => Api.updateMyName(name));
    }
  }
}
