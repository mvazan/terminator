import 'package:flutter/material.dart';

import '../../data/providers.dart';

/// First sign-in: validate the team invite code and pick a display name.
/// The very first member is auto-approved (founder), everyone else waits
/// for a one-tap approval from any member.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _joining = false;

  Future<void> _join() async {
    final code = _code.text.trim();
    final name = _name.text.trim();
    if (code.isEmpty || name.isEmpty) {
      _snack('Vyplň kód týmu i své jméno.');
      return;
    }
    setState(() => _joining = true);
    try {
      await Api.joinTeam(code, name);
      // AuthGate re-routes automatically via the profile stream.
    } catch (e) {
      final message = '$e'.contains('invalid_invite_code')
          ? 'Neplatný kód týmu.'
          : 'Nepovedlo se: $e';
      _snack(message);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vítej v Termínátoru'),
        actions: [
          TextButton(onPressed: Api.signOut, child: const Text('Odhlásit')),
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
                Text(
                  'Ještě tě neznáme. Zadej kód naší party a své jméno.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
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
                  onSubmitted: (_) => _join(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _joining ? null : _join,
                  child: Text(_joining ? 'Přidávám…' : 'Přidat se k týmu'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
