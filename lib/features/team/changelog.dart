import 'package:flutter/material.dart';

/// User-facing release notes, newest first — shown by tapping the version
/// line at the bottom of the Tým tab. Kept by hand: add an entry with every
/// release (versions match the git tags).
class Release {
  const Release(this.version, this.date, this.changes);

  final String version;
  final String date;
  final List<String> changes;
}

const appChangelog = <Release>[
  Release('1.1.7', '8. 7. 2026', [
    'Oprava: po přihlášení kódem z e-mailu se turnaje i členové týmu '
        'teď načtou správně.',
  ]),
  Release('1.1.6', '8. 7. 2026', [
    'Nový (prázdný) chat se řadí podle času založení, nepadá na konec.',
    'Ťuknutím na verzi v záložce Tým se zobrazí tento přehled novinek.',
  ]),
  Release('1.1.5', '8. 7. 2026', [
    'Chaty se řadí podle poslední zprávy a ukazují počet nepřečtených.',
    'U objednávky jde zadat počet míst na start — klidně víc, '
        'než se zatím hlásí lidí.',
    'Při přidávání hráčů na start jsou ti, kdo se na něj hlásili, nahoře.',
  ]),
  Release('1.1.4', '8. 7. 2026', [
    'Přihlášení kódem z e-mailu, když odkaz nefunguje '
        '(např. v aplikaci Seznamu).',
    'Dole v záložce Tým je vidět verze aplikace.',
  ]),
  Release('1.1.3', '7. 7. 2026', [
    'Upozornění „dá se objednat" chodí jako jeden souhrn za turnaj, '
        'ne řada zpráv při odklikávání.',
  ]),
  Release('1.1.2', '7. 7. 2026', [
    'Ťuknutí na upozornění otevře rovnou daný turnaj nebo chat.',
    'Když přihlašovací odkaz nefunguje, aplikace ukáže proč.',
  ]),
  Release('1.1.1', '7. 7. 2026', [
    'Ikona aplikace a úvodní obrazovka s maskotem.',
    'Archivované turnaje jsou jen ke čtení a jdou duplikovat '
        'pro novou sezónu.',
    'Přepínač „kdo je přihlášený" ukáže jména pod termíny.',
    'Políčko termínu ukazuje „nás/volné dráhy" u turnajů s webem.',
    'České přihlašovací e-maily.',
  ]),
  Release('1.1.0', '6. 7. 2026', [
    'Termíny a obsazenost se načítají z webu kuželny '
        '(kkmoravskaslavia.cz).',
    'Vlastní skupiny dnů s různými časy startů.',
    'Kontakty na pořadatele (e-mail, telefon, web) přímo v turnaji.',
    'Nový vzhled včetně tmavého režimu.',
  ]),
  Release('1.0.0', '6. 7. 2026', [
    'První verze: turnaje, „kdy můžeš", hlasování, objednávky, '
        'sestavy, chaty a upozornění.',
  ]),
];

/// Bottom sheet with the release history.
void showChangelog(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text('Co je nového',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final release in appChangelog) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(
                'verze ${release.version} · ${release.date}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final change in release.changes)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text('• $change'),
              ),
          ],
        ],
      ),
    ),
  );
}
