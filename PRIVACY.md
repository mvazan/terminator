# Zásady ochrany osobních údajů — Termínátor

_Poslední aktualizace: 10. 8. 2026_

Termínátor je soukromá aplikace pro jeden kuželkářský tým, sloužící ke
koordinaci turnajů. Přístup je pouze na pozvání (kód týmu a schválení
členem). Tento dokument popisuje, jaké údaje aplikace zpracovává a proč.

## Jaké údaje zpracováváme

- **E-mailová adresa** — slouží výhradně k přihlášení (přihlašovací odkaz /
  kód zaslaný e-mailem). Nepoužívá se k marketingu.
- **Zobrazované jméno** — jak tě zná parta; zadáváš ho při prvním přihlášení.
- **Údaje o používání v rámci týmu** — dostupnost na termíny, objednávky,
  zprávy v týmovém chatu, sestavy. Vidí je pouze schválení členové týmu.
- **Token pro push notifikace (FCM)** — technický identifikátor zařízení,
  aby aplikace mohla posílat upozornění. Neváže se na žádné reklamní profily.
- **Diagnostická data o pádech** — když aplikace narazí na chybu, odešle se
  technický záznam (typ chyby, model zařízení, verze systému a aplikace), aby
  šlo chybu najít a opravit. Neobsahuje obsah tvých zpráv ani přihlašovací
  údaje a neslouží k marketingu.
- **Přístup ke Google kalendáři (jen když si ho sám propojíš)** — dobrovolná
  funkce v Nastavení. Po tvém souhlasu uchováváme na serveru přístupový token
  (refresh token), identifikátor kalendáře, který ti aplikace v Google účtu
  vytvoří, a e-mail propojeného účtu (jen pro zobrazení v nastavení).

## Google kalendář

Propojení je volitelné a vypnuté, dokud ho sám nezapneš. Aplikace používá
oprávnění `calendar.app.created`, které jí dovoluje pracovat **výhradně
s kalendářem „Termínátor", který si sama vytvoří** — na tvé ostatní kalendáře
a jejich události nevidí a nijak s nimi nenakládá.

Do tohoto kalendáře zapisujeme jen tvoje starty z aplikace (název turnaje,
kuželna a její adresa, datum a čas) a mažeme je, když se objednávka zruší nebo
tě někdo ze sestavy odebere. Data z kalendáře nikam dál nepředáváme a
nepoužíváme je k žádnému jinému účelu.

Propojení můžeš kdykoli zrušit v Nastavení („Odpojit"), případně i v
nastavení svého Google účtu. Odpojením odvoláme token a smažeme ho ze serveru;
samotný kalendář a jeho události ti v Google účtu zůstanou, dokud si je
nesmažeš sám.

## K čemu údaje slouží

Výhradně k fungování aplikace: přihlášení, zobrazení týmových dat schváleným
členům a zasílání upozornění, která si uživatel může kdykoli vypnout v
nastavení.

## Kde jsou údaje uloženy

Data jsou uložena v službě **Supabase** (PostgreSQL, region EU — Frankfurt).
Přenos je šifrovaný (HTTPS). Push notifikace odesílá **Firebase Cloud
Messaging** (Google). E-maily s přihlašovacím odkazem odesílá poskytovatel
SMTP (Gmail). Diagnostická data o pádech aplikace zpracovává služba
**Sentry** (Functional Software, Inc.) výhradně pro hlášení a opravu chyb.
Pokud sis propojil Google kalendář, komunikuje server také s **Google
Calendar API** (Google) — jen kvůli zápisu a mazání tvých startů ve vytvořeném
kalendáři.

## Sdílení údajů

Údaje **nesdílíme ani neprodáváme** třetím stranám. Jsou přístupné pouze
schváleným členům téhož týmu v rámci aplikace a výše uvedeným technickým
poskytovatelům (Supabase, Google/Firebase, Google Calendar, Sentry) nezbytným
pro provoz a pro hlášení chyb.

## Uchování a smazání

Data se uchovávají po dobu používání aplikace týmem. O smazání svého účtu a
souvisejících dat můžeš požádat na kontaktu níže; správce týmu může člena také
skrýt/odebrat přímo v aplikaci.

## Kontakt

Dotazy k ochraně údajů: **milos.vazan@gmail.com**
