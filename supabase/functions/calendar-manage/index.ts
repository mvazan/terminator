// calendar-manage — akce nad propojeným kalendářem, které si vyžádal
// uživatel a musí doběhnout, než mu appka ukáže výsledek.
//
// `disconnect` a `reminders`. Nasazuje se BEZ --no-verify-jwt (na rozdíl od
// notify a calendar-oauth-callback): volá ji přihlášený člověk z appky přes
// functions.invoke, který přikládá jeho JWT, a platforma ho ověří ještě před
// spuštěním. Uvnitř se stejně ptáme auth.getUser() — bez session totiž klient
// pošle jen anon klíč a ten žádného uživatele nedá.
//
// Proč synchronně a ne jobem jako dřív (0031): odpojení má nejdřív SMAZAT
// kalendář v Googlu a teprve pak odvolat token — po revoke už appka na
// kalendář nikdy nedosáhne (calendarList.list 403, calendars.get 404 přes
// hranici grantu, ověřeno 2026-08-10). Minutový cron mezitím nechával okno,
// ve kterém dlaždice nabízela „Propojit"; kdo ho stihl, dostal osiřelý
// kalendář navíc. Tady se stav mění až po odpovědi, takže není co stihnout.
//
// Selhání, které jde zopakovat (Google 5xx, síť), NIC nezmění a vrátí chybu —
// nikdy nezůstane půlka odpojení.

import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  deleteCalendar,
  GoogleAuthError,
  refreshAccessToken,
  revokeToken,
  writeFutureStarts,
} from "../_shared/google_calendar.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;

const admin = createClient(
  SUPABASE_URL,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/** Zapomene propojení: tokeny pryč, řádek zůstává jako 'unlinked' i s
 * reminder_minutes, ať se připomínky po novém propojení samy obnoví.
 * Google e-mail je osobní údaj — po odpojení pro něj není důvod. */
async function forget(userId: string) {
  await admin.from("google_calendar_tokens").delete().eq("user_id", userId);
  await admin.from("google_calendar_links")
    .update({
      status: "unlinked",
      google_email: null,
      last_error: null,
      updated_at: new Date().toISOString(),
    })
    .eq("user_id", userId);
}

async function disconnect(userId: string): Promise<Response> {
  const { data: token } = await admin.from("google_calendar_tokens")
    .select("refresh_token, google_calendar_id")
    .eq("user_id", userId).maybeSingle();

  // Nic k odpojení (nikdy nepropojeno / už hotovo / druhé ťuknutí) nebo je
  // uložený jen token bez kalendáře (spadlé propojení) — jen uklidit.
  if (!token?.refresh_token) {
    await forget(userId);
    return json({ orphaned: false });
  }
  const calendarId = token.google_calendar_id as string | null;

  let accessToken: string | null = null;
  try {
    accessToken = await refreshAccessToken(token.refresh_token as string);
  } catch (error) {
    if (!(error instanceof GoogleAuthError && error.code === "invalid_grant")) {
      console.error(`disconnect: token refresh failed for ${userId}:`, error);
      return json({ error: "google_unavailable" }, 503);
    }
    // Přístup je pryč (odvolaný v Google účtu, prošlý). Kalendář smazat
    // nejde — a už nikdy nepůjde; řekneme to a uklidíme aspoň u nás.
    console.warn(`disconnect: grant already revoked for ${userId}`);
    await forget(userId);
    return json({ orphaned: !!calendarId });
  }

  if (calendarId) {
    const result = await deleteCalendar(accessToken, calendarId);
    if (result === "retry") {
      // Nic jsme nezměnili — ať to člověk zkusí znovu, stav zůstal celý.
      return json({ error: "google_unavailable" }, 503);
    }
    // "ok" (i 404/410 = už je pryč) i "auth"/"gone" znamenají, že tenhle
    // kalendář nemáme jak dál mazat; pokračujeme úklidem.
    if (result !== "ok") {
      console.warn(`disconnect: calendar delete ended as ${result}`);
    }
  }

  await revokeToken(token.refresh_token as string);
  await forget(userId);
  return json({ orphaned: false });
}

/** Uloží preferenci připomínek a HNED ji propíše do všech budoucích startů.
 * Připomínky nesou samotné události (calendarList je pod tímhle scope
 * zakázaný), takže „změnit připomínku" = přepsat události. Přes joby to
 * trvalo dvě otočky minutového cronu (~2 min) a působilo to, jako by se nic
 * nedělo; člověk se dívá, tak to uděláme rovnou. Co by selhalo, dožene
 * job — vrací se počet přepsaných a případný zbytek. */
async function setReminders(
  userId: string,
  minutes: number[],
): Promise<Response> {
  // Normalizaci a validaci dělá RPC (0030) — ta je zdrojem pravdy i pro
  // staré buildy; tady jen zavoláme totéž jménem uživatele.
  const { error } = await admin.rpc("set_calendar_reminders_for", {
    p_user_id: userId,
    p_minutes: minutes,
  });
  if (error) {
    console.error(`set reminders failed for ${userId}:`, error);
    return json({ error: "bad_reminders" }, 400);
  }

  const { data: link } = await admin.from("google_calendar_links")
    .select("status, reminder_minutes").eq("user_id", userId).maybeSingle();
  const saved = (link?.reminder_minutes as number[] | null) ?? [];
  if (link?.status !== "linked") return json({ rewritten: 0, saved });

  const { data: token } = await admin.from("google_calendar_tokens")
    .select("refresh_token, google_calendar_id")
    .eq("user_id", userId).maybeSingle();
  if (!token?.refresh_token || !token.google_calendar_id) {
    return json({ rewritten: 0, saved });
  }

  let accessToken: string;
  try {
    accessToken = await refreshAccessToken(token.refresh_token as string);
  } catch (_) {
    // Preference je uložená; události dožene job, až se Google umoudří.
    await admin.rpc("backfill_calendar_jobs", { p_user_id: userId });
    return json({ rewritten: 0, saved, deferred: true });
  }

  const written = await writeFutureStarts(
    admin,
    userId,
    accessToken,
    token.google_calendar_id as string,
  );
  const { data: total } = await admin.rpc("my_future_starts", {
    p_user_id: userId,
  });
  const failed = written < ((total ?? []) as unknown[]).length;
  // Co neprošlo, dožene job — preference je uložená, takže se neztratí.
  if (failed) await admin.rpc("backfill_calendar_jobs", { p_user_id: userId });
  return json({ rewritten: written, saved, deferred: failed });
}

Deno.serve(async (request) => {
  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization) return json({ error: "unauthorized" }, 401);

    // Klient s uživatelovým JWT — jen kvůli zjištění, KDO volá. Zápisy pak
    // dělá service-role klient (RLS na těchhle tabulkách klienta nepouští).
    const asUser = createClient(
      SUPABASE_URL,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authorization } } },
    );
    const { data: { user } } = await asUser.auth.getUser();
    if (!user) return json({ error: "unauthorized" }, 401);

    const body = await request.json().catch(() => ({}));
    if (body?.action === "disconnect") return await disconnect(user.id);
    if (body?.action === "reminders") {
      const minutes = Array.isArray(body.minutes)
        ? body.minutes.map((m: unknown) => Number(m)).filter(Number.isFinite)
        : [];
      return await setReminders(user.id, minutes);
    }
    return json({ error: "unknown_action" }, 400);
  } catch (error) {
    console.error("calendar-manage failed:", error);
    return json({ error: "internal" }, 500);
  }
});
