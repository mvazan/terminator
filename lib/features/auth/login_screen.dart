import 'package:flutter/material.dart';

import '../../config.dart';
import '../../core/ui.dart';
import '../../data/providers.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      snack(context, 'Zadej platný e-mail.');
      return;
    }
    setState(() => _sending = true);
    final ok = await tryAction(
        context, () => Api.sendMagicLink(email, AppConfig.authRedirectUrl));
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) _sent = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('🎳', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 8),
                  Text('Termínátor',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium),
                  Text('Hasta la vista, prázdná dráha.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 32),
                  if (_sent) ...[
                    const Icon(Icons.mark_email_read_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Hotovo! Poslali jsme ti e-mail.\n'
                      'Otevři ho v telefonu a klikni na odkaz.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => setState(() => _sent = false),
                      child: const Text('Poslat znovu / jiný e-mail'),
                    ),
                  ] else ...[
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Tvůj e-mail',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _sending ? null : _send,
                      child: Text(_sending
                          ? 'Odesílám…'
                          : 'Poslat přihlašovací odkaz'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Žádné heslo. Přijde ti e-mail s odkazem, '
                      'kliknutím se přihlásíš.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
