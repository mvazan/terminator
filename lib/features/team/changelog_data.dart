// Release-notes data — pure Dart (no Flutter import) so CI tooling
// (tool/whatsnew.dart) can read it without a Flutter runtime. The UI that
// renders these lives in changelog.dart.

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
  Release('2.0.7', '14. 7. 2026', [
    'Seznam turnajů: kratší řádek s přihláškami — např. „7 lidí · nej shoda '
        '2 lidé · obj. termínů: 1".',
  ]),
  Release('2.0.6', '14. 7. 2026', [
    'Mapa se otevírá zvlášť: „Mapa kuželen" z obrazovky Kuželny, „Mapa '
        'turnajů" z Turnajů (bez přepínače).',
    'Seznam turnajů: řádek s přihláškami zase ukazuje „nejsilnější den" a '
        'nově i počet objednaných termínů.',
  ]),
  Release('2.0.5', '14. 7. 2026', [
    'Mapa turnajů: skryté turnaje se ve výchozím stavu nezobrazují — přepneš '
        'je ikonou oka vpravo nahoře.',
    'Detail skrytého turnaje je jen ke čtení (bez přihlašování); skrytí '
        'zrušíš v menu.',
  ]),
  Release('2.0.4', '14. 7. 2026', [
    'Mapa turnajů: přibyla legenda (ikona ⓘ vpravo nahoře) a opravilo se '
        'otevírání šedých špendlíků (skryté a proběhlé turnaje).',
  ]),
  Release('2.0.3', '14. 7. 2026', [
    'Mapa má nový barevný režim (ikona vpravo nahoře): jedna kuželna = jeden '
        'turnaj, barva podle stavu — zelená běží, oranžová se blíží, šedá je '
        'minulá; tmavší odstín = jsi přihlášený nebo máš start.',
    'V seznamu turnajů přibyl počet objednaných termínů a řádek s přihláškami '
        'je kratší.',
    'Detail turnaje: u probíhajícího se skryjí odehrané dny; po skončení '
        'zůstane přehled, kdo byl kde přihlášený.',
  ]),
  Release('2.0.1', '13. 7. 2026', [
    'Drobná údržba na pozadí (příprava zveřejnění v Google Play).',
  ]),
  Release('2.0.0', '13. 7. 2026', [
    'Appka teď umí víc týmů: při prvním přihlášení jde „Založit nový tým" — '
        'dostaneš kód pro partu a PIN správy. Nový tým aktivuje správce '
        'aplikace.',
    'Kód pro pozvání party je vidět v záložce Tým.',
    'Data týmů jsou úplně oddělená — každá parta vidí jen to svoje.',
  ]),
  Release('1.3.8', '13. 7. 2026', [
    'Nová kartička turnaje: data od–do vlevo, kuželna výrazně, pod ní název '
        'a typ · disciplína.',
    'Bez internetu appka řekne lidsky „vypadá to, že jsi offline" místo '
        'chybové hlášky.',
    'Skrývání: seznam se nepřeskupuje pod prstem (skryté se přesunou až po '
        'uložení) a offline se skrývání nedá spustit.',
    'Správné skloňování: „1 člověk může".',
  ]),
  Release('1.3.7', '13. 7. 2026', [
    'Oprava „celý den" — funguje i když už máš v dni něco zakliknuté.',
    'Kartička turnaje: název turnaje dole přes celou šířku; počty lidí '
        'čitelněji („nejsilnější den 2 lidé").',
    'Ikona zeměkoule obráceně: přeškrtnutá jen u turnajů BEZ webu.',
    'Sezónní kalendář: čárky jen na dnech, kdy můžeš ty, a objednaných '
        '(míň šumu).',
    'Offline pruh se ukazuje na všech obrazovkách, i v detailech.',
  ]),
  Release('1.3.6', '13. 7. 2026', [
    'Seznam turnajů: kuželna je hlavní nadpis, u turnaje vidíš kolik lidí '
        'se hlásí (i nejsilnější den) a levý proužek značí, že máš něco '
        'zakliknuté.',
    'Skrývání přes oko: zaškrtáváš lokálně a uloží se najednou při zavření; '
        'skryté řadí nakonec. Skrytí turnaje zruší i tvoje zakliknuté '
        'termíny (s upozorněním).',
    'V detailu jde zakliknout celý den jedním tlačítkem.',
    'Vyměněný význam: ✓ = dost lidí na objednání, zvýrazněný rámeček = '
        'tvoje volba.',
    '„Kdo je přihlášený" ukazuje souhrn za osobu (celý den / od 17:00 / '
        '12:00–15:00).',
    'Sezónní kalendář: svislé čárky = dny se starty (tmavá) a objednané '
        'dny (červená); okem jde zobrazit i skryté turnaje šedě.',
    'Nová mapa kuželen s piny a nadcházejícími turnaji.',
    'Upozornění jdou nastavit „jen tiše" (bez zvuku, jen lišta a tečka).',
    'Aplikace funguje offline pro čtení — ukáže poslední známá data.',
    'Tlačítka ukazují průběh a pomalé připojení už nezasekne akce.',
    'Výběr kuželny už nepřepisuje web turnaje.',
  ]),
  Release('1.3.5', '10. 7. 2026', [
    'Oprava: v sezónním kalendáři se zase kreslí barevné pruhy turnajů '
        '(v 1.3.4 zmizely).',
  ]),
  Release('1.3.4', '10. 7. 2026', [
    'Nový chat „Celý tým" — společný chat celé party, vždy nahoře v seznamu '
        'chatů.',
    'Skrývání turnajů, které tě nezajímají: ikona oka v seznamu turnajů '
        'ukáže všechny se zaškrtávátky. Skrytý turnaj zmizí jen tobě — '
        'i s chatem a upozorněními.',
    'Sezónní kalendář vybarvuje týdny přesně podle dní (turnaj pá–ne už '
        'nezabírá celý týden).',
    'Automatické hlášení chyb, ať je umíme rychleji opravit.',
  ]),
  Release('1.3.3', '9. 7. 2026', [
    'Oprava obsazenosti u turnajů z turnajekuzelky.cz: u „dvojic" a „čtveřic" '
        'se počítají místa hráčů, ne starty — 2×120HS se dvěma volnými starty '
        'ukáže 0/4.',
  ]),
  Release('1.3.2', '9. 7. 2026', [
    'Ikona zeměkoule u turnajů z webu se přesunula do pravého rohu.',
  ]),
  Release('1.3.1', '9. 7. 2026', [
    'Turnaje načítané z webu poznáš v seznamu podle ikony zeměkoule.',
    'Nový typ „trojice" a disciplína „40HS".',
    'Při archivaci se k názvu turnaje doplní rok, aby se příští ročník '
        'nepletl.',
    'Oprava odkazů na pozvánky z kuzelky.cz (otevíraly 404).',
  ]),
  Release('1.3.0', '9. 7. 2026', [
    'V nastavení upozornění je skryté „Návrhy termínů" (hlasování je zatím '
        'vypnuté) a srozumitelnější popis „Nově vypsané turnaje".',
  ]),
  Release('1.2.9', '9. 7. 2026', [
    'Radar nových turnajů hlídá i kkmoravskaslavia.cz.',
  ]),
  Release('1.2.8', '9. 7. 2026', [
    'Nové upozornění „Nově vypsané turnaje" (výchozí vypnuto) — appka 2× '
        'denně hlídá turnajekuzelky.cz a kuzelky.cz a dá vědět o nových. '
        'Zapneš v Tým → Nastavení.',
  ]),
  Release('1.2.7', '9. 7. 2026', [
    'Předvyplnění z odkazu funguje i pro kkmoravskaslavia.cz (název, typ, '
        'disciplína).',
  ]),
  Release('1.2.6', '9. 7. 2026', [
    'Načítání turnajů z webu turnajekuzelky.cz (termíny i obsazenost).',
    'Při zakládání turnaje stačí nahoře vložit odkaz — název, typ, '
        'disciplínu i termíny předvyplní appka.',
  ]),
  Release('1.2.5', '9. 7. 2026', [
    'Ťuknutí na upozornění „nový člen" teď otevře záložku Tým.',
  ]),
  Release('1.2.4', '9. 7. 2026', [
    'Údržba a vyčištění pod kapotou (bez viditelných změn).',
    'Oprava: upozornění (push) po přesunu serveru zase chodí.',
  ]),
  Release('1.2.3', '8. 7. 2026', [
    'Přesun serveru blíž k nám (rychlejší odezva).',
  ]),
  Release('1.2.2', '8. 7. 2026', [
    'Když je u turnaje adresa kuželny, jde na ni spustit navigaci.',
    'Drobná údržba pod kapotou.',
  ]),
  Release('1.2.1', '8. 7. 2026', [
    'Počet drah se teď skloňuje správně (1 dráha, 2 dráhy, 5 drah).',
    'Drobná údržba pod kapotou.',
  ]),
  Release('1.2.0', '8. 7. 2026', [
    'U turnaje přibyla disciplína (60/100/120/180HS nebo jiné).',
    'Kuželna u turnaje je teď povinná a vybírá se ze seznamu; termín '
        'od–do se zadává jedním výběrem.',
    'Kuželny: počet drah se vybírá (2/4/6/8), kontakty pořadatele zůstávají '
        'u turnaje (na kuželně jen web domácího oddílu).',
    'Zadávání objednávky: přehlednější řádky startů, klikací jen '
        'zaškrtávátko.',
    'Odhlášení se teď ptá na potvrzení.',
  ]),
  Release('1.1.9', '8. 7. 2026', [
    'U objednávky vybíráš počet drah na start — nejvýš tolik, kolik jich '
        'kuželna má (u turnajů s webem po počet volných drah).',
    'V tandemu drží jedna dráha 2 hráče, takže na ni jde přiřadit dvojnásobek.',
  ]),
  Release('1.1.8', '8. 7. 2026', [
    'Kuželny: ulož si kuželnu (počet drah, adresa, kontakty) a vyber ji '
        'u turnaje. Spravují se v Tým → Nastavení → Kuželny.',
    'Nejsilnější termíny jsou teď nahoře nad rozvrhem.',
    'Tlačítko na objednávku se jmenuje „Zadat objednávku"; hlasování je '
        'zatím skryté.',
  ]),
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
