# Zásady ochrany osobních údajů — Termínátor

_Poslední aktualizace: 9. 7. 2026_

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

## K čemu údaje slouží

Výhradně k fungování aplikace: přihlášení, zobrazení týmových dat schváleným
členům a zasílání upozornění, která si uživatel může kdykoli vypnout v
nastavení.

## Kde jsou údaje uloženy

Data jsou uložena v službě **Supabase** (PostgreSQL, region EU — Frankfurt).
Přenos je šifrovaný (HTTPS). Push notifikace odesílá **Firebase Cloud
Messaging** (Google). E-maily s přihlašovacím odkazem odesílá poskytovatel
SMTP (Gmail).

## Sdílení údajů

Údaje **nesdílíme ani neprodáváme** třetím stranám. Jsou přístupné pouze
schváleným členům téhož týmu v rámci aplikace a výše uvedeným technickým
poskytovatelům (Supabase, Google/Firebase) nezbytným pro provoz.

## Uchování a smazání

Data se uchovávají po dobu používání aplikace týmem. O smazání svého účtu a
souvisejících dat můžeš požádat na kontaktu níže; správce týmu může člena také
skrýt/odebrat přímo v aplikaci.

## Kontakt

Dotazy k ochraně údajů: **ai-dev-1@ngft.com**
