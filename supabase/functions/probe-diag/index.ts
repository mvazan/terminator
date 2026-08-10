import { createClient } from "jsr:@supabase/supabase-js@2";
import { refreshAccessToken } from "../_shared/google_calendar.ts";
const GUARD = "37ed011f250dca03c36d7c37d5cef75d7bdc06793c27bd7e";
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
Deno.serve(async (req) => {
  if (new URL(req.url).searchParams.get("g") !== GUARD) return new Response("no", { status: 403 });
  const { data: links } = await db.from("google_calendar_links")
    .select("user_id, status, last_error, reminder_minutes, updated_at");
  const { data: jobs } = await db.from("notification_jobs")
    .select("kind, dedupe_key, attempts, run_at");
  const { data: toks } = await db.from("google_calendar_tokens").select("user_id, refresh_token, google_calendar_id");
  const events: Record<string, unknown> = {};
  for (const t of toks ?? []) {
    try {
      const token = await refreshAccessToken(t.refresh_token as string);
      const r = await fetch(
        `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(t.google_calendar_id as string)}/events?maxResults=10`,
        { headers: { Authorization: `Bearer ${token}` } });
      const b = r.ok ? await r.json() : await r.text();
      events[(t.user_id as string).slice(0,8)] = r.ok
        ? (b.items ?? []).map((e: {summary?: string; reminders?: unknown; updated?: string}) =>
            ({ s: (e.summary ?? "").slice(0, 24), rem: e.reminders, upd: e.updated }))
        : { status: r.status };
    } catch (e) { events[(t.user_id as string).slice(0,8)] = { err: String(e).slice(0,100) }; }
  }
  return Response.json({
    now: new Date().toISOString(),
    links: (links ?? []).map((l) => ({ u:(l.user_id as string).slice(0,8), s:l.status, e:l.last_error, r:l.reminder_minutes, upd:l.updated_at })),
    jobs: (jobs ?? []).map((j) => ({ k:j.kind, key:(j.dedupe_key as string).slice(0,44), att:j.attempts, run:j.run_at })),
    events,
  });
});
