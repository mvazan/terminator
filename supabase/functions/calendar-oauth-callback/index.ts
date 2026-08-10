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
  createSecondaryCalendar,
  emailFromIdToken,
  exchangeCode,
} from "../_shared/google_calendar.ts";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

/** Musí BYTE PO BYTU sedět s redirect_uri v appce (Api.calendarConsentUrl)
 * i s Authorized redirect URI v Google Cloud Console. */
const REDIRECT_URI =
  `${Deno.env.get("SUPABASE_URL")}/functions/v1/calendar-oauth-callback`;

/** Appka nemá deep-link router (login-callback si bere supabase_flutter sama),
 * takže se nikam nevracíme — jen řekneme, že je hotovo. Dlaždice v nastavení
 * se překlopí sama přes Realtime, jakmile se sem dopíše výsledek. */
function page(ok: boolean, message: string, status = 200): Response {
  return new Response(
    `<!DOCTYPE html>
<html lang="cs"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Termínátor</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 26rem;
         margin: 3rem auto; padding: 0 1.25rem; text-align: center;
         line-height: 1.5; color: #1b1b1b; background: #fafafa; }
  h1 { font-size: 1.35rem; margin-bottom: .5rem; }
  p.hint { color: #666; font-size: .95rem; }
  @media (prefers-color-scheme: dark) {
    body { color: #f2f2f2; background: #161616; }
    p.hint { color: #a0a0a0; }
  }
</style></head>
<body>
<h1>${ok ? "Kalendář propojen ✅" : "Propojení se nepovedlo"}</h1>
<p>${message}</p>
<p class="hint">Tuhle záložku můžeš zavřít a vrátit se do appky.</p>
</body></html>`,
    { status, headers: { "Content-Type": "text/html; charset=utf-8" } },
  );
}

Deno.serve(async (request) => {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");

  if (url.searchParams.get("error")) {
    return page(false, "Souhlas v Googlu jsi zrušil(a).");
  }
  if (!code || !state) {
    return page(false, "Odkaz je neúplný.", 400);
  }

  // 1. Nonce -> uživatel, na kterého byl vázán (a spotřebování na jedno použití).
  const { data: userId, error: nonceError } = await supabase
    .rpc("consume_calendar_nonce", { p_nonce: state });
  if (nonceError) {
    // Chyba volání (třeba chybějící grant) není totéž co propadlý odkaz —
    // říct člověku „zkus to znovu" by ho poslalo do nekonečné smyčky.
    console.error("consume_calendar_nonce failed:", nonceError);
    return page(false, "Interní chyba při ověření odkazu.", 500);
  }
  if (!userId) {
    return page(
      false,
      "Odkaz vypršel nebo už byl použitý. Zkus propojení znovu z appky.",
      400,
    );
  }

  // 2. Výměna kódu za tokeny.
  let tokens;
  try {
    tokens = await exchangeCode(code, REDIRECT_URI);
  } catch (error) {
    console.error("code exchange failed:", error);
    return page(false, "Nepovedlo se domluvit s Googlem. Zkus to znovu.", 502);
  }
  if (!tokens.refreshToken) {
    // Appka posílá access_type=offline&prompt=consent, takže refresh token
    // přijít má. Když nepřijde, radši hlasitě selhat než tiše uložit půlku.
    console.error("no refresh_token in token response");
    return page(
      false,
      "Google nevrátil potřebné oprávnění. Zkus propojení znovu.",
      502,
    );
  }

  const now = new Date().toISOString();
  const { error: tokenError } = await supabase.from("google_calendar_tokens")
    .upsert({
      user_id: userId,
      refresh_token: tokens.refreshToken,
      google_calendar_id: null,
      updated_at: now,
    });
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
    return page(false, "Interní chyba při ukládání.", 500);
  }

  // 3. Kalendář zakládáme hned, ne přes job: člověk se dívá a čekat pár minut
  // na „propojeno" by bylo divné. Když to spadne, token zůstane uložený
  // (status pending) a stačí zkusit propojení znovu bez nového souhlasu.
  try {
    const calendarId = await createSecondaryCalendar(tokens.accessToken);
    await supabase.from("google_calendar_tokens")
      .update({ google_calendar_id: calendarId, updated_at: now })
      .eq("user_id", userId);
    await supabase.from("google_calendar_links")
      .update({ status: "linked", updated_at: now })
      .eq("user_id", userId);
    const { data: enqueued } = await supabase
      .rpc("backfill_calendar_jobs", { p_user_id: userId });
    console.log(`calendar linked for ${userId}, backfilled ${enqueued} jobs`);
    return page(
      true,
      "Tvoje budoucí starty se do pár minut objeví v kalendáři Termínátor.",
    );
  } catch (error) {
    console.error("calendar creation failed:", error);
    await supabase.from("google_calendar_links")
      .update({ last_error: "Kalendář se nepodařilo založit.", updated_at: now })
      .eq("user_id", userId);
    return page(
      false,
      "Účet je propojený, ale kalendář se nepodařilo založit. " +
        "Zkus to prosím za chvíli znovu z nastavení.",
      500,
    );
  }
});
