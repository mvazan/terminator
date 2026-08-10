// calendar-oauth-callback — návrat z Google OAuth souhlasu.
//
// Veřejný GET (deploy s --no-verify-jwt): Google k přesměrování Supabase JWT
// přiložit neumí. Důvěru nese jednorázový `state` nonce z start_calendar_link()
// (0027) — neuhodnutelný, na jedno použití, TTL 10 minut, vydaný jen
// přihlášenému schválenému členovi. Tady se rozhoduje o tokenu, takže tokeny
// odsud NIKDY nejdou ven k appce: uloží se do google_calendar_tokens a appka
// vidí jen stav v google_calendar_links.
//
// Vyžaduje secrets: GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET.
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY se injektují automaticky.

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  calendarExists,
  createSecondaryCalendar,
  emailFromIdToken,
  exchangeCode,
  writeFutureStarts,
} from "../_shared/google_calendar.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

/** Musí BYTE PO BYTU sedět s redirect_uri v appce (Api.calendarConsentUrl)
 * i s Authorized redirect URI v Google Cloud Console. */
const REDIRECT_URI =
  `${Deno.env.get("SUPABASE_URL")}/functions/v1/calendar-oauth-callback`;

/** Výsledek ukazujeme na statické stránce na GitHub Pages, ne přímo odsud:
 * edge runtime přepisuje Content-Type na text/plain (a posílá nosniff), takže
 * HTML vrácené touhle funkcí se prohlížeči zobrazí jako zdroják včetně
 * rozsypané diakritiky. Přesměrování projde beze změny.
 *
 * Do appky se nevracíme deep linkem (žádný router v ní není, login-callback
 * si bere supabase_flutter sám) — dlaždice v nastavení se překlopí sama přes
 * Realtime, jakmile se sem dopíše výsledek. */
const RESULT_PAGE = "https://mvazan.github.io/terminator/calendar-linked";

type Stav = "ok" | "zruseno" | "odkaz" | "google" | "kalendar" | "chyba";

function page(stav: Stav): Response {
  return Response.redirect(`${RESULT_PAGE}?stav=${stav}`, 302);
}

Deno.serve(async (request) => {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");

  if (url.searchParams.get("error")) {
    return page("zruseno");
  }
  if (!code || !state) {
    return page("odkaz");
  }

  // 1. Nonce -> uživatel, na kterého byl vázán (a spotřebování na jedno použití).
  const { data: userId, error: nonceError } = await supabase
    .rpc("consume_calendar_nonce", { p_nonce: state });
  if (nonceError) {
    // Chyba volání (třeba chybějící grant) není totéž co propadlý odkaz —
    // říct člověku „zkus to znovu" by ho poslalo do nekonečné smyčky.
    console.error("consume_calendar_nonce failed:", nonceError);
    return page("chyba");
  }
  if (!userId) {
    return page("odkaz");
  }

  // 2. Výměna kódu za tokeny.
  let tokens;
  try {
    tokens = await exchangeCode(code, REDIRECT_URI);
  } catch (error) {
    console.error("code exchange failed:", error);
    return page("google");
  }
  if (!tokens.refreshToken) {
    // Appka posílá access_type=offline&prompt=consent, takže refresh token
    // přijít má. Když nepřijde, radši hlasitě selhat než tiše uložit půlku.
    console.error("no refresh_token in token response");
    return page("google");
  }

  // Id kalendáře z minula, PŘED přepsáním tokenů: kandidát na znovupoužití.
  // (Preference připomínek řádek taky přežívá — odpojení ho jen zbavuje
  // tokenů — a doveze si ji každá událost, kterou backfill níž založí.)
  const { data: previous } = await supabase.from("google_calendar_tokens")
    .select("google_calendar_id").eq("user_id", userId).maybeSingle();
  const previousCalendarId = previous?.google_calendar_id as string | null;
  const now = new Date().toISOString();
  const { error: tokenError } = await supabase.from("google_calendar_tokens")
    .upsert({
      user_id: userId,
      refresh_token: tokens.refreshToken,
      google_calendar_id: previousCalendarId,
      updated_at: now,
    });
  // reminder_minutes se schválně NEPOSÍLÁ: on-conflict přepisuje jen poslané
  // sloupce, takže preference přežije i tenhle upsert.
  const { error: linkError } = await supabase.from("google_calendar_links")
    .upsert({
      user_id: userId,
      status: "pending",
      google_email: emailFromIdToken(tokens.idToken),
      last_error: null,
      updated_at: now,
    });
  if (tokenError || linkError) {
    console.error("link save failed:", tokenError ?? linkError);
    return page("chyba");
  }

  // 3. Kalendář řešíme hned, ne přes job: člověk se dívá a čekat pár minut
  // na „propojeno" by bylo divné. Když to spadne, token zůstane uložený
  // (status pending) a stačí zkusit propojení znovu bez nového souhlasu.
  // Uvnitř ŽIVÉHO grantu se dřívější kalendář znovupoužije (opakované
  // „Zkusit znovu" tak nedělá duplicity); přes hranici odvolaného souhlasu
  // na něj appka nedosáhne (get 404) a vzniká čerstvý.
  try {
    const reusable = previousCalendarId &&
      await calendarExists(tokens.accessToken, previousCalendarId);
    const calendarId = reusable
      ? previousCalendarId
      : await createSecondaryCalendar(tokens.accessToken);
    await supabase.from("google_calendar_tokens")
      .update({ google_calendar_id: calendarId, updated_at: now })
      .eq("user_id", userId);
    await supabase.from("google_calendar_links")
      .update({ status: "linked", updated_at: now })
      .eq("user_id", userId);

    // Starty zapisujeme rovnou, ne přes joby: člověk po propojení otevře
    // kalendář a chce v něm vidět svoje starty, ne prázdno a „ono to za
    // minutu naskočí". Připomínky si nesou samy události (calendarList je
    // pod tímhle scope zakázaný), takže tohle je zároveň jejich obnova.
    // Co by selhalo, dožene job — proto se enqueuje i tak.
    const { data: enqueued } = await supabase
      .rpc("backfill_calendar_jobs", { p_user_id: userId });
    const written = await writeFutureStarts(
      supabase,
      userId,
      tokens.accessToken,
      calendarId,
    );
    console.log(
      `calendar linked for ${userId} (${reusable ? "reused" : "created"}), ` +
        `${written} starts written, ${enqueued} jobs queued as backup`,
    );
    return page("ok");
  } catch (error) {
    console.error("calendar creation failed:", error);
    await supabase.from("google_calendar_links")
      .update({ last_error: "Kalendář se nepodařilo založit.", updated_at: now })
      .eq("user_id", userId);
    return page("kalendar");
  }
});
