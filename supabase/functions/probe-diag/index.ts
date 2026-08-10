// Dočasná diagnostika: KTERÉ volání pod scope calendar.app.created selhává.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { refreshAccessToken } from "../_shared/google_calendar.ts";
const GUARD = "56a3f51a4f81c1b92627a9b80fbfdfd7e1001e7337b2f992";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const API = "https://www.googleapis.com/calendar/v3";

Deno.serve(async (req) => {
  const u = new URL(req.url);
  if (u.searchParams.get("g") !== GUARD) return new Response("no", { status: 403 });
  const who = u.searchParams.get("u") ?? "";
  const { data: rows } = await db.from("google_calendar_tokens")
    .select("user_id, refresh_token, google_calendar_id");
  const row = (rows ?? []).find((r) => (r.user_id as string).startsWith(who));
  if (!row) return Response.json({ error: "no such user" });

  const out: Record<string, unknown> = { user: (row.user_id as string).slice(0, 8) };
  let token: string;
  try { token = await refreshAccessToken(row.refresh_token as string); }
  catch (e) { return Response.json({ ...out, refresh: "FAILED " + String(e).slice(0, 150) }); }
  out.refresh = "ok";
  const cal = row.google_calendar_id as string;
  const H = { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };

  const get = await fetch(`${API}/calendars/${encodeURIComponent(cal)}`, { headers: H });
  out.calendars_get = get.status;

  const clGet = await fetch(`${API}/users/me/calendarList/${encodeURIComponent(cal)}`, { headers: H });
  out.calendarList_get = clGet.status;

  const clPatch = await fetch(`${API}/users/me/calendarList/${encodeURIComponent(cal)}`, {
    method: "PATCH", headers: H,
    body: JSON.stringify({ defaultReminders: [{ method: "popup", minutes: 1440 }] }),
  });
  out.calendarList_patch = clPatch.status;
  if (!clPatch.ok) out.calendarList_patch_body = (await clPatch.text()).slice(0, 300);

  // Zápis události (a hned úklid), ať víme, jestli sync vůbec může fungovat.
  const evId = "probe" + "0123456789abcdefghij".slice(0, 12);
  const ins = await fetch(`${API}/calendars/${encodeURIComponent(cal)}/events`, {
    method: "POST", headers: H,
    body: JSON.stringify({ id: evId, summary: "probe (smaž mě)",
      start: { dateTime: "2027-01-01T10:00:00", timeZone: "Europe/Prague" },
      end: { dateTime: "2027-01-01T11:00:00", timeZone: "Europe/Prague" } }),
  });
  out.events_insert = ins.status;
  if (!ins.ok) out.events_insert_body = (await ins.text()).slice(0, 300);
  else {
    const del = await fetch(`${API}/calendars/${encodeURIComponent(cal)}/events/${evId}`,
      { method: "DELETE", headers: { Authorization: `Bearer ${token}` } });
    out.events_delete = del.status;
  }
  return Response.json(out);
});
