import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ui.dart';
import '../../data/providers.dart';

/// First sign-in, two paths:
/// - join an existing team by invite code (first member of a team is
///   auto-approved, everyone else waits for a one-tap member approval);
/// - found a NEW team: name it, get a generated invite code + manage PIN,
///   then wait for the app owner (superadmin) to approve the team.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _code = TextEditingController();
  final _teamName = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  bool _createMode = false;

  @override
  void dispose() {
    _code.dispose();
    _teamName.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    final name = _name.text.trim();
    if (code.isEmpty || name.isEmpty) {
      snack(context, 'Vyplň kód týmu i své jméno.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Api.joinTeam(code, name);
      // AuthGate re-routes automatically via the profile stream.
    } catch (e) {
      if (mounted) {
        snack(
            context,
            '$e'.contains('invalid_invite_code')
                ? 'Neplatný kód týmu.'
                : friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final teamName = _teamName.text.trim();
    final name = _name.text.trim();
    if (teamName.isEmpty || name.isEmpty) {
      snack(context, 'Vyplň název týmu i své jméno.');
      return;
    }
    setState(() => _busy = true);
    try {
      final team = await Api.createTeam(teamName, name);
      if (!mounted) return;
      // Show the generated credentials ONCE, prominently — the founder needs
      // the code to invite the team and the PIN for manage mode.
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Tým založen 🎳'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ulož si tyhle údaje a pošli kód partě:'),
              const SizedBox(height: 12),
              SelectableText('Kód týmu: ${team.inviteCode}\n'
                  'PIN správy: ${team.managePin}'),
              const SizedBox(height: 12),
              const Text(
                'Tým teď musí schválit správce aplikace — dostal upozornění. '
                'Než ho schválí, appka počká na obrazovce schvalování.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(
                    text: 'Kód týmu: ${team.inviteCode} · '
                        'PIN správy: ${team.managePin}'));
                snack(dialogContext, 'Zkopírováno.');
              },
              child: const Text('Kopírovat'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Rozumím'),
            ),
          ],
        ),
      );
      // AuthGate re-routes to the team-approval waiting screen.
    } catch (e) {
      if (mounted) {
        snack(
            context,
            '$e'.contains('already_member')
                ? 'Už jsi členem týmu.'
                : 'Nepovedlo se: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vítej v Termínátoru'),
        actions: [
          TextButton(
              onPressed: () => confirmSignOut(context),
              child: const Text('Odhlásit')),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: false, label: Text('Přidat se k týmu')),
                    ButtonSegment(value: true, label: Text('Založit nový tým')),
                  ],
                  selected: {_createMode},
                  onSelectionChanged: (s) =>
                      setState(() => _createMode = s.first),
                ),
                const SizedBox(height: 20),
                Text(
                  _createMode
                      ? 'Založ vlastní tým — kód pro partu a PIN správy '
                          'vygenerujeme.'
                      : 'Zadej kód party a své jméno.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                if (_createMode)
                  TextField(
                    controller: _teamName,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Název týmu',
                      border: OutlineInputBorder(),
                    ),
                  )
                else
                  TextField(
                    controller: _code,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Kód týmu',
                      border: OutlineInputBorder(),
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Tvoje jméno (jak tě parta zná)',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _createMode ? _create() : _join(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : (_createMode ? _create : _join),
                  child: Text(_busy
                      ? (_createMode ? 'Zakládám…' : 'Přidávám…')
                      : (_createMode ? 'Založit tým' : 'Přidat se k týmu')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
