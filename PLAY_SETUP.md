# Termínátor → Google Play (Internal testing)

Cieľ: distribuovať appku partii cez **Internal testing** — appka není verejně
vyhľadatelná, prístup len cez pozvánku, žiadna recenzia Google, žiadne
12-testerov-pravidlo. Testeri dostanú automatické updaty.

Appka je technicky pripravená: applicationId `cz.kuzelky.terminator`, podpis
vlastným keystorom, `targetSdk 36` (nad Play minimom), a CI teraz stavia aj
**AAB** (`terminator-vX.Y.Z.aab`) vedľa APK.

## 1. Google Play Console (jednorazovo)
- Účet už máš overený. V <https://play.google.com/console> vytvor appku:
  - Názov: **Termínátor**, jazyk čeština, typ: App, zdarma.
  - Odklikaj úvodné dotazníky (App/Game, Free/Paid…).

## 2. Nahraj AAB do Internal testing
- **Testing → Internal testing → Create new release**.
- Zapni **Play App Signing** (Google prevezme podpisový kľúč; tvoj keystore sa
  stane „upload key" — netreba nič meniť v projekte).
- Nahraj `terminator-vX.Y.Z.aab` (stiahni z GitHub Releases po tagu).
- **Testers**: vytvor zoznam e-mailov partie (ich Google účty), alebo skopíruj
  opt-in link a pošli ho im.

## 3. Povinné minimum pre Internal testing
Play vyžaduje aj pri internom testovaní pár vecí (raz):
- **App content** (ľavé menu → Policy → App content):
  - **Privacy policy URL** — appka zbiera e-mail + posiela push, tak je
    povinná. (Vygenerovaný text je v tomto repe: `PRIVACY.md` — nahraj ho ako
    verejnú stránku, napr. GitHub Pages / Gist raw / kdekoľvek s HTTPS URL.)
  - **Data safety** — deklaruj: zbieraš **E-mailovú adresu** (na prihlásenie,
    nie zdieľané, šifrované pri prenose) a **App activity / push token**
    (na notifikácie). Nič sa nepredáva.
  - **Ads**: nie. **Target audience**: dospelí. **Content rating**: vyplň
    krátky dotazník (žiadne násilie atď.).
- **App access**: appka je za invite kódom → daj Googlu **testovací prístup**:
  napíš, že po prihlásení treba zadať kód týmu, a uveď funkčný kód (`veverky`).
  (Pri internom testingu to nie je vždy vynucované, ale nezaškodí.)

## 4. Store listing (stačí minimum)
- Krátky popis + celý popis (česky).
- **Ikona 512×512** (máš `assets/icon/icon.png` — 1024px, stačí zmenšiť).
- **Feature graphic 1024×500**.
- **Aspoň 2 screenshoty telefónu** (nafoť z appky: zoznam turnajov, detail).

## 5. Publish
- **Review and roll out** internal release. Internal testing je live do pár
  minút (žiadna recenzia).
- Pošli testerom opt-in link → nainštalujú z Play, updaty automaticky.

## Ľudia bez Google účtu?
Prakticky nikto — Android telefón Google účet má (Play je predinštalovaný).
Keby predsa, priame APK (`terminator-vX.Y.Z.apk` z Releases) funguje ďalej.

## Ako vydať novú verziu
1. Bump `version:` v pubspec.yaml (patch podľa pravidiel), commit.
2. `git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z` → CI postaví AAB+APK.
3. V Play Console → Internal testing → Create new release → nahraj nový AAB →
   roll out. (Verzia musí mať vyšší `+build` číslo než predošlá.)
