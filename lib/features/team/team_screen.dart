import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/busy.dart';
import '../../core/ui.dart';
import '../../data/providers.dart';
import '../../domain/models.dart';
import '../manage/manage_mode.dart';
import 'changelog.dart';
import 'settings_screen.dart';

final _packageInfoProvider =
    FutureProvider((_) => PackageInfo.fromPlatform());

/// Team overview: my profile, pending approvals (anyone can approve — the
/// everyone-equal rule), member list, sign-out.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myProfileProvider).value;
    final team = ref.watch(myTeamProvider);
    final pendingTeams =
        (me?.superadmin ?? false) ? ref.watch(pendingTeamsProvider) : const <Team>[];
    final members = ref.watch(membersProvider).value ?? const [];
    final pending = [for (final m in members) if (!m.isApproved) m];
    final approved = [for (final m in members) if (m.isApproved) m];
    final manage = ref.watch(manageUnlockedProvider);
    // Hidden members are filtered out of membersProvider; fetch them raw only
    // in manage mode so they can be unhidden.
    final hidden = manage
        ? (ref.watch(allMembersProvider).value ?? const [])
            .where((m) => m.isHidden)
            .toList()
        : const <Profile>[];

    return Scaffold(
      appBar: AppBar(
        // Long-press the title to reach the hidden manage mode (PIN-gated).
        title: GestureDetector(
          onLongPress: () => handleManageGesture(context, ref),
          child: const Text('Tým'),
        ),
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
          // The team's invite code, always at hand for inviting the rest of
          // the party (long-tap the code text to copy via SelectableText).
          if (team != null)
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: Text(team.name),
              subtitle: SelectableText('Kód pro pozvání: ${team.inviteCode}'),
            ),
          const Divider(),
          // Superadmin only: teams awaiting activation.
          if (pendingTeams.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Týmy ke schválení',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final t in pendingTeams)
              ListTile(
                leading: const Icon(Icons.group_add_outlined),
                title: Text(t.name),
                subtitle: const Text('čeká na schválení a přidělení kódu'),
                trailing: FilledButton(
                  child: const Text('Schválit'),
                  onPressed: () async {
                    // The superadmin names the team's invite code here.
                    final code = await promptText(
                      context,
                      title: 'Kód pro tým ${t.name}',
                      hint: 'např. veverky',
                      confirmLabel: 'Schválit tým',
                    );
                    if (code == null || code.isEmpty || !context.mounted) {
                      return;
                    }
                    await tryAction(
                        context, () => Api.approveTeam(t.id, code),
                        success: 'Tým ${t.name} schválen — kód: $code');
                  },
                ),
              ),
            const Divider(),
          ],
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
                trailing: BusyFilledButton(
                  label: const Text('Schválit'),
                  onPressed: () async {
                    await tryAction(context, () => Api.approveMember(m.id),
                        success: '${m.displayName} schválen(a). Vítej!');
                  },
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
              trailing: manage && m.id != me?.id
                  ? IconButton(
                      icon: const Icon(Icons.visibility_off_outlined),
                      tooltip: 'Skrýt hráče',
                      onPressed: () => _confirmHideMember(context, m),
                    )
                  : null,
            ),
          if (hidden.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Skrytí (${hidden.length})',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final m in hidden)
              ListTile(
                dense: true,
                leading: const Icon(Icons.visibility_off, size: 20),
                title: Text(m.displayName),
                subtitle: const Text('po zobrazení čeká na schválení'),
                trailing: BusyTextButton(
                  label: const Text('Zobrazit'),
                  onPressed: () async {
                    await tryAction(
                        context, () => Api.setMemberHidden(m.id, false),
                        success: '${m.displayName} zobrazen(a) — '
                            'čeká na schválení.');
                  },
                ),
              ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Odhlásit se'),
            onTap: () => confirmSignOut(context),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Termínátor 🎳 — Hasta la vista, prázdná dráha.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                if (ref.watch(_packageInfoProvider).value case final info?)
                  InkWell(
                    onTap: () => showChangelog(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        'verze ${info.version} (build ${info.buildNumber})'
                        ' · co je nového?',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editName(BuildContext context, Profile me) async {
    final name = await promptText(context,
        title: 'Tvoje jméno', initial: me.displayName);
    if (name != null && name.isNotEmpty && context.mounted) {
      await tryAction(context, () => Api.updateMyName(name));
    }
  }

  Future<void> _confirmHideMember(BuildContext context, Profile m) async {
    final ok = await confirmDialog(
      context,
      title: 'Skrýt hráče?',
      message: '„${m.displayName}" zmizí ze seznamu a při dalším přihlášení '
          'bude znovu čekat na schválení. Skrytí jde vrátit tady '
          'v režimu správy.',
      confirmLabel: 'Skrýt',
    );
    if (ok && context.mounted) {
      await tryAction(context, () => Api.setMemberHidden(m.id, true),
          success: '${m.displayName} skryt(a).');
    }
  }
}
