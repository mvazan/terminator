// notify — the single push-notification Edge Function.
//
// Triggered by Supabase Database Webhooks (see SETUP.md) on:
//   INSERT profiles      -> "new member waiting for approval"
//   INSERT tournaments   -> "new tournament"
//   UPDATE orders        -> "cancelled" (to the order's people only; new
//                           orders are silent — deferred jobs speak instead)
//   INSERT messages      -> chat message (skips muted users and the author)
//   INSERT availability  -> threshold check: slot just reached min players
//                           (event-driven; dedup via slots.threshold_notified_at)
//   CRON notification_jobs -> deferred jobs (0025): assigned/removed player
//                           notices and the order free-spots digest
//
// Sends via FCM HTTP v1. Requires secrets:
//   FIREBASE_SERVICE_ACCOUNT — the service-account JSON (one line)
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import { createClient } from "jsr:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// ---------------------------------------------------------------------------
// FCM HTTP v1 auth: mint an OAuth2 access token from the service account.
// ---------------------------------------------------------------------------

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

const serviceAccount: ServiceAccount = JSON.parse(
  Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "{}",
);

let cachedToken: { token: string; expiresAt: number } | null = null;

function base64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string"
    ? new TextEncoder().encode(data)
    : data;
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt > now + 60) {
    return cachedToken.token;
  }

  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const key = await importPrivateKey(serviceAccount.private_key);
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  ));
  const jwt = `${header}.${claims}.${base64url(signature)}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!response.ok) {
    throw new Error(`OAuth token failed: ${await response.text()}`);
  }
  const json = await response.json();
  cachedToken = { token: json.access_token, expiresAt: now + 3500 };
  return json.access_token;
}

// ---------------------------------------------------------------------------
// Sending
// ---------------------------------------------------------------------------

// Android notification channels created by the app — loud (default) and
// silent (no sound/vibration, tray + badge dot). Keep in sync with
// lib/push/push.dart (Push.channelLoud / Push.channelSilent).
const CHANNEL_LOUD = "terminator";
const CHANNEL_SILENT = "terminator_silent";

async function sendToTokens(
  tokens: { userId: string; token: string; silent?: boolean }[],
  title: string,
  body: string,
  // Tap routing for the app (FCM data values must be strings):
  // kind + tournament_id (+ day for day chats). See lib/push/push.dart.
  data: Record<string, string> = {},
  // Same tag = the new notification replaces the old one in the tray
  // (Android). Used so a tournament never stacks threshold notifications.
  tag?: string,
  // Data-only delivery: title/body ride inside `data` and the APP renders
  // the notification (needed for the inline reply action on chat pushes —
  // system-drawn notifications can't carry actions). Requires client >= 45.
  dataOnly = false,
) {
  if (tokens.length === 0) return;
  const accessToken = await getAccessToken();
  const url =
    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

  await Promise.all(tokens.map(async ({ userId, token, silent }) => {
    // Per-recipient channel: their per-kind pref decides loud vs silent.
    const channel = silent ? CHANNEL_SILENT : CHANNEL_LOUD;
    const response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          ...(dataOnly ? {} : { notification: { title, body } }),
          // `channel` also travels in data so the app's local rendering
          // picks the same channel; data-only carries title/body/tag too.
          data: {
            ...data,
            channel,
            ...(dataOnly ? { title, body, ...(tag ? { tag } : {}) } : {}),
          },
          android: {
            priority: "HIGH",
            ...(dataOnly ? {} : {
              notification: {
                channel_id: channel,
                ...(tag ? { tag } : {}),
              },
            }),
          },
        },
      }),
    });
    if (!response.ok) {
      const text = await response.text();
      console.error(`FCM send failed for ${userId}: ${text}`);
      if (text.includes("UNREGISTERED") || text.includes("INVALID_ARGUMENT")) {
        await supabase.from("profiles").update({ fcm_token: null })
          .eq("id", userId);
      }
    }
  }));
}

type NotificationKind =
  | "new_member"
  | "new_tournament"
  | "proposal"
  | "order"
  | "chat"
  | "threshold"
  | "new_public_tournament"
  | "new_team";

// Kinds that are opt-in: silent unless the member enabled them in settings.
//
// The kind list and the default-off rule live in THREE places that must stay
// in sync: this file, NotificationKind in lib/domain/models.dart, and the
// kind CHECK constraint in supabase/migrations (0001 baseline + later ones).
const DEFAULT_OFF: NotificationKind[] = [
  "new_member",
  "threshold",
  "new_public_tournament",
];

/**
 * All approved members' tokens for one notification kind, honoring
 * notification_prefs. Default-on kinds: missing row = send; a row can
 * disable or mute. Default-off kinds: only members whose row enables the
 * kind (and isn't muted) receive it.
 */
async function teamTokens(
  kind: NotificationKind,
  exclude: (string | null | undefined)[] = [],
  // Scope recipients to one team. Omitted = global (radar: public data,
  // per-user opt-in prefs already gate it).
  teamId?: string,
  // Further restrict to an explicit member set (day chats: only people going
  // that day). Omitted = the whole team.
  memberIds?: Set<string> | null,
): Promise<{ userId: string; token: string; silent: boolean }[]> {
  let profilesQuery = supabase
    .from("profiles")
    .select("id, fcm_token")
    .eq("status", "approved")
    .not("fcm_token", "is", null);
  if (teamId) profilesQuery = profilesQuery.eq("team_id", teamId);
  const [profilesResult, prefsResult] = await Promise.all([
    profilesQuery,
    supabase
      .from("notification_prefs")
      .select("user_id, enabled, muted_until, silent")
      .eq("kind", kind),
  ]);
  if (profilesResult.error) throw profilesResult.error;
  if (prefsResult.error) throw prefsResult.error;

  const now = Date.now();
  const excluded = new Set(exclude.filter(Boolean));
  const activeRows = new Set<string>();
  const silentUsers = new Set<string>();
  for (const pref of prefsResult.data ?? []) {
    const muted = pref.muted_until !== null &&
      Date.parse(pref.muted_until) > now;
    if (pref.enabled && !muted) activeRows.add(pref.user_id);
    if (!pref.enabled || muted) excluded.add(pref.user_id);
    if (pref.enabled && !muted && pref.silent) silentUsers.add(pref.user_id);
  }

  const optIn = DEFAULT_OFF.includes(kind);
  return (profilesResult.data ?? [])
    .filter((p) => !memberIds || memberIds.has(p.id))
    .filter((p) =>
      optIn ? activeRows.has(p.id) : !excluded.has(p.id)
    )
    .map((p) => ({
      userId: p.id,
      token: p.fcm_token as string,
      silent: silentUsers.has(p.id),
    }));
}

/**
 * Superadmins' tokens (team approvals go only to them), honoring their
 * notification_prefs like everyone else's.
 */
async function superadminTokens(
  kind: NotificationKind,
): Promise<{ userId: string; token: string; silent: boolean }[]> {
  const [profilesResult, prefsResult] = await Promise.all([
    supabase
      .from("profiles")
      .select("id, fcm_token")
      .eq("superadmin", true)
      .not("fcm_token", "is", null),
    supabase
      .from("notification_prefs")
      .select("user_id, enabled, muted_until, silent")
      .eq("kind", kind),
  ]);
  if (profilesResult.error) throw profilesResult.error;
  if (prefsResult.error) throw prefsResult.error;

  const now = Date.now();
  const excluded = new Set<string>();
  const silentUsers = new Set<string>();
  for (const pref of prefsResult.data ?? []) {
    const muted = pref.muted_until !== null &&
      Date.parse(pref.muted_until) > now;
    if (!pref.enabled || muted) excluded.add(pref.user_id);
    if (pref.enabled && !muted && pref.silent) silentUsers.add(pref.user_id);
  }
  return (profilesResult.data ?? [])
    .filter((p) => !excluded.has(p.id))
    .map((p) => ({
      userId: p.id,
      token: p.fcm_token as string,
      silent: silentUsers.has(p.id),
    }));
}

/**
 * User ids who hid this tournament for themselves ("not interested") — they
 * should get none of its pushes. Pass the result into teamTokens' exclude list.
 */
async function hidersOf(tournamentId: string): Promise<string[]> {
  const { data, error } = await supabase
    .from("tournament_hides")
    .select("user_id")
    .eq("tournament_id", tournamentId);
  if (error) throw error;
  return (data ?? []).map((r) => r.user_id as string);
}

function dayLabel(sqlDate: string): string {
  const names = ["ne", "po", "út", "st", "čt", "pá", "so"];
  const d = new Date(`${sqlDate}T00:00:00Z`);
  return `${names[d.getUTCDay()]} ${d.getUTCDate()}.${d.getUTCMonth() + 1}.`;
}

function timeLabel(sqlTime: string): string {
  const [h, m] = sqlTime.split(":");
  return `${Number(h)}:${m}`;
}

// ---------------------------------------------------------------------------
// Event handlers
// ---------------------------------------------------------------------------

type WebhookPayload = {
  type: "INSERT" | "UPDATE" | "DELETE" | "CRON";
  table: string;
  record: Record<string, unknown> | null;
  old_record: Record<string, unknown> | null;
};

// ---------------------------------------------------------------------------
// Deferred-notification jobs (see 0025_notification_jobs.sql). The DB
// debounces and cancels; here every handler REVALIDATES reality before
// sending, so a stale job can never produce a wrong push.
// ---------------------------------------------------------------------------

type OrderContext = {
  order: { id: string; status: string; tournament_id: string;
    created_by: string };
  tournament: { name: string; team_id?: string; kind: string };
  slots: { id: string; date: string; time: string }[];
  rosterUserIds: (string | null)[];
  rosterBySlot: Map<string, number>;
  lanesBySlot: Map<string, number>;
};

/** Everything a job handler needs about one ACTIVE order; null when the
 * order is gone or cancelled (job silently expires). */
async function orderContext(orderId: unknown): Promise<OrderContext | null> {
  const { data: order } = await supabase.from("orders")
    .select("id, status, tournament_id, created_by")
    .eq("id", orderId as string).maybeSingle();
  if (!order || !["ordered", "confirmed"].includes(order.status as string)) {
    return null;
  }
  const [{ data: t }, { data: os }] = await Promise.all([
    supabase.from("tournaments").select("name, team_id, kind")
      .eq("id", order.tournament_id).single(),
    supabase.from("order_slots").select("slot_id, lanes")
      .eq("order_id", order.id),
  ]);
  const slotIds = (os ?? []).map((r) => r.slot_id as string);
  if (slotIds.length === 0 || !t) return null;
  const [{ data: slots }, { data: rosterRows }] = await Promise.all([
    supabase.from("slots").select("id, date, time").in("id", slotIds),
    supabase.from("rosters").select("slot_id, user_id").in("slot_id", slotIds),
  ]);
  const rosterBySlot = new Map<string, number>();
  for (const r of rosterRows ?? []) {
    const id = r.slot_id as string;
    rosterBySlot.set(id, (rosterBySlot.get(id) ?? 0) + 1);
  }
  return {
    order: order as OrderContext["order"],
    tournament: t as OrderContext["tournament"],
    slots: ((slots ?? []) as OrderContext["slots"]).sort((a, b) =>
      `${a.date} ${a.time}`.localeCompare(`${b.date} ${b.time}`)),
    rosterUserIds: (rosterRows ?? []).map((r) => r.user_id as string | null),
    rosterBySlot,
    lanesBySlot: new Map(
      (os ?? []).map((r) => [r.slot_id as string, r.lanes as number])),
  };
}

function whenLabel(ctx: OrderContext): string {
  return ctx.slots
    .map((s) => `${dayLabel(s.date)} ${timeLabel(s.time)}`)
    .join(" · ");
}

function placesLabel(n: number): string {
  if (n === 1) return "1 volné místo";
  if (n >= 2 && n <= 4) return `${n} volná místa`;
  return `${n} volných míst`;
}

async function displayName(userId: unknown): Promise<string | null> {
  if (!userId) return null;
  const { data } = await supabase.from("profiles").select("display_name")
    .eq("id", userId as string).maybeSingle();
  return (data?.display_name as string | null) ?? null;
}

/** "You were assigned" — sent only if the player is STILL on the order. */
async function jobAssigned(payload: Record<string, unknown>) {
  const ctx = await orderContext(payload.order_id);
  const userId = payload.user_id as string;
  if (!ctx || !ctx.rosterUserIds.includes(userId)) return;
  const adder = await displayName(payload.added_by);
  await sendToTokens(
    await teamTokens("order", [], ctx.tournament.team_id,
      new Set([userId])),
    `Hraješ: ${ctx.tournament.name}`,
    `${whenLabel(ctx)}${adder ? ` — přidal(a) tě ${adder}.` : ""}`,
    { kind: "order", tournament_id: ctx.order.tournament_id },
  );
}

/** "You were removed" — only if they're really off the whole order. */
async function jobRemoved(payload: Record<string, unknown>) {
  const ctx = await orderContext(payload.order_id);
  const userId = payload.user_id as string;
  if (!ctx || ctx.rosterUserIds.includes(userId)) return;
  await sendToTokens(
    await teamTokens("order", [], ctx.tournament.team_id,
      new Set([userId])),
    `Už nehraješ: ${ctx.tournament.name}`,
    `Byl(a) jsi odebrán(a) ze startu ${whenLabel(ctx)}.`,
    { kind: "order", tournament_id: ctx.order.tournament_id },
  );
}

/** Free-spots digest: full order = silence; otherwise ping teammates who
 * aren't on it (and don't hide the tournament). */
async function jobFreeSpots(payload: Record<string, unknown>) {
  const ctx = await orderContext(payload.order_id);
  if (!ctx) return;
  const playersPerLane = ctx.tournament.kind === "tandem" ? 2 : 1;
  let free = 0;
  for (const [slotId, lanes] of ctx.lanesBySlot) {
    free += Math.max(
      0, lanes * playersPerLane - (ctx.rosterBySlot.get(slotId) ?? 0));
  }
  if (free <= 0) return;
  const hiders = await hidersOf(ctx.order.tournament_id);
  await sendToTokens(
    await teamTokens("order",
      [ctx.order.created_by, ...ctx.rosterUserIds, ...hiders],
      ctx.tournament.team_id),
    `${ctx.tournament.name}: volná místa`,
    `${whenLabel(ctx)} — ${placesLabel(free)}, přidej se.`,
    { kind: "order", tournament_id: ctx.order.tournament_id },
    `order-${ctx.order.id}`,
  );
}

/** Cron entry: run every due job once, then drop it (handlers revalidate,
 * so dropping after a handler error only ever loses a convenience push). */
async function processJobs() {
  const { data: jobs } = await supabase.from("notification_jobs")
    .select("id, kind, payload")
    .lte("run_at", new Date().toISOString())
    .limit(100);
  for (const job of jobs ?? []) {
    try {
      const payload = job.payload as Record<string, unknown>;
      switch (job.kind as string) {
        case "assigned":
          await jobAssigned(payload);
          break;
        case "removed":
          await jobRemoved(payload);
          break;
        case "order_free_spots":
          await jobFreeSpots(payload);
          break;
        default:
          console.error(`unknown job kind: ${job.kind}`);
      }
    } catch (error) {
      console.error(`job ${job.kind}/${job.id} failed:`, error);
    }
    await supabase.from("notification_jobs").delete().eq("id", job.id);
  }
}

/** Tournament name + owning team, one fetch — every per-tournament push
 * needs both (title + recipient scoping). */
async function tournamentInfo(
  id: unknown,
): Promise<{ name: string; teamId?: string }> {
  const { data } = await supabase.from("tournaments").select("name, team_id")
    .eq("id", id).single();
  return {
    name: (data?.name as string) ?? "turnaj",
    teamId: data?.team_id as string | undefined,
  };
}

async function handle(payload: WebhookPayload) {
  const record = payload.record ?? {};

  switch (payload.table) {
    case "notification_jobs": {
      // Minutely cron (0025) — process everything that's due.
      await processJobs();
      return;
    }

    case "profiles": {
      if (payload.type !== "INSERT" || record.status !== "pending") return;
      await sendToTokens(
        await teamTokens("new_member", [record.id as string],
          record.team_id as string | undefined),
        "Nový člen čeká na schválení",
        `${record.display_name} se chce přidat. Schval ho v záložce Tým.`,
        { kind: "new_member" },
      );
      return;
    }

    case "teams": {
      if (payload.type !== "INSERT" || record.status !== "pending") return;
      await sendToTokens(
        await superadminTokens("new_team"),
        "Nový tým čeká na schválení",
        `${record.name} — schval ho v záložce Tým.`,
        { kind: "new_team" },
      );
      return;
    }

    case "tournaments": {
      if (payload.type !== "INSERT") return;
      await sendToTokens(
        await teamTokens("new_tournament", [record.created_by as string],
          record.team_id as string | undefined),
        "Nový turnaj 🎳",
        `${record.name} — odklikej si termíny!`,
        { kind: "new_tournament", tournament_id: record.id as string },
      );
      return;
    }

    case "tournament_radar": {
      if (payload.type !== "INSERT" || record.suppressed === true) return;
      const disc = record.discipline ? ` (${record.discipline})` : "";
      await sendToTokens(
        await teamTokens("new_public_tournament", []),
        "Nově vypsaný turnaj 🗓️",
        `${record.name}${disc} — nový turnaj na turnajekuzelky.cz.`,
        { kind: "new_public_tournament", url: record.url as string },
      );
      return;
    }

    case "orders": {
      const status = record.status as string;
      const oldStatus = payload.old_record?.status as string | undefined;
      const isNewProposal = payload.type === "INSERT" &&
        status === "proposed";
      const isOrdered = status === "ordered" &&
        (payload.type === "INSERT" || oldStatus === "proposed");
      const isCancelled = payload.type === "UPDATE" &&
        status === "cancelled" && oldStatus !== "cancelled";
      if (!isNewProposal && !isOrdered && !isCancelled) return;

      const [{ name, teamId }, hiders] = await Promise.all([
        tournamentInfo(record.tournament_id),
        hidersOf(record.tournament_id as string),
      ]);
      const orderData = {
        kind: "order",
        tournament_id: record.tournament_id as string,
      };
      // Proposals are gone from the app — no push for a stray one. A fresh
      // order is silent too: the deferred free-spots job (enqueued by a DB
      // trigger, processed below in processJobs) speaks for it 3 minutes
      // later, once the creator has had time to assign people.
      if (isNewProposal || isOrdered) return;
      // Cancelled: only the people ON the order (and its creator) care.
      const { data: os } = await supabase.from("order_slots")
        .select("slot_id").eq("order_id", record.id as string);
      const slotIds = (os ?? []).map((r) => r.slot_id as string);
      const affected = new Set<string>([record.created_by as string]);
      if (slotIds.length > 0) {
        const { data: rosterRows } = await supabase.from("rosters")
          .select("user_id").in("slot_id", slotIds);
        for (const r of rosterRows ?? []) {
          if (r.user_id) affected.add(r.user_id as string);
        }
      }
      await sendToTokens(
        await teamTokens("order", hiders, teamId, affected),
        `Zrušeno: ${name}`,
        "Objednávka byla zrušena.",
        orderData,
      );
      return;
    }

    case "messages": {
      if (payload.type !== "INSERT") return;
      const tournamentId = record.tournament_id as string;
      const day = record.day as string | null;

      let mutesQuery = supabase.from("chat_mutes").select("user_id")
        .eq("tournament_id", tournamentId);
      mutesQuery = day === null
        ? mutesQuery.is("day", null)
        : mutesQuery.eq("day", day);

      // Tournament info, this chat's mutes, hiders, and the author are all
      // independent lookups.
      const [{ name, teamId }, { data: mutes }, hiders, { data: author }] =
        await Promise.all([
          tournamentInfo(tournamentId),
          mutesQuery,
          hidersOf(tournamentId),
          supabase.from("profiles")
            .select("display_name").eq("id", record.user_id).single(),
        ]);

      const title = day === null
        ? `${name}`
        : `${name} — ${dayLabel(day)}`;
      // Day chats are closed groups — notify only their members (rostered
      // that day ∪ order creator ∪ fans, minus leavers). Tournament chats
      // (day === null) still reach the whole team.
      let memberIds: Set<string> | undefined;
      if (day !== null) {
        const { data: members, error } = await supabase.rpc("day_member_ids", {
          p_tournament: tournamentId,
          p_day: day,
        });
        if (error) throw error;
        memberIds = new Set(
          (members ?? []).map((m) => m.user_id as string),
        );
      }
      await sendToTokens(
        await teamTokens("chat", [
          record.user_id as string,
          ...(mutes ?? []).map((m) => m.user_id as string),
          ...hiders,
        ], teamId, memberIds),
        title,
        `${author?.display_name ?? "?"}: ${record.body}`,
        {
          kind: "chat",
          tournament_id: tournamentId,
          ...(day === null ? {} : { day }),
        },
        undefined,
        true, // data-only → the app draws it with the inline reply
      );
      return;
    }

    case "team_messages": {
      if (payload.type !== "INSERT") return;
      const [{ data: muters }, { data: author }] = await Promise.all([
        supabase.from("team_chat_mutes").select("user_id"),
        supabase.from("profiles")
          .select("display_name").eq("id", record.user_id).single(),
      ]);
      await sendToTokens(
        await teamTokens("chat", [
          record.user_id as string,
          ...(muters ?? []).map((m) => m.user_id as string),
        ], record.team_id as string | undefined),
        "Celý tým",
        `${author?.display_name ?? "?"}: ${record.body}`,
        { kind: "team_chat" },
        undefined,
        true, // data-only → the app draws it with the inline reply
      );
      return;
    }

    case "availability": {
      if (payload.type !== "INSERT") return;
      const slotId = record.slot_id as string;

      const { data: slot } = await supabase.from("slots")
        .select("id, date, time, threshold_notified_at, tournament_id")
        .eq("id", slotId).single();
      if (!slot || slot.threshold_notified_at !== null) return;

      const [{ count }, { data: tournament }] = await Promise.all([
        supabase.from("availability")
          .select("*", { count: "exact", head: true })
          .eq("slot_id", slotId),
        supabase.from("tournaments").select("name, min_players, team_id")
          .eq("id", slot.tournament_id).single(),
      ]);
      if (!tournament || (count ?? 0) < tournament.min_players) return;

      // Per-slot dedup: only the writer that flips the flag continues.
      const { data: flipped } = await supabase.from("slots")
        .update({ threshold_notified_at: new Date().toISOString() })
        .eq("id", slotId)
        .is("threshold_notified_at", null)
        .select("id");
      if (!flipped || flipped.length === 0) return;

      // Per-tournament cooldown: one ticking wave = one summary push.
      // Slots crossing the minimum during the window are absorbed silently
      // (their flag above is already set); the summary lists everything
      // orderable anyway, and the app shows the live grid.
      const COOLDOWN_MINUTES = 20;
      const cutoff = new Date(Date.now() - COOLDOWN_MINUTES * 60_000)
        .toISOString();
      const { data: cooldown } = await supabase.from("tournaments")
        .update({ threshold_notified_at: new Date().toISOString() })
        .eq("id", slot.tournament_id)
        .or(`threshold_notified_at.is.null,threshold_notified_at.lt.${cutoff}`)
        .select("id");
      if (!cooldown || cooldown.length === 0) return;

      // Summarize every upcoming slot that currently has enough players.
      const today = new Date().toISOString().slice(0, 10);
      const { data: slots } = await supabase.from("slots")
        .select("id, date, time")
        .eq("tournament_id", slot.tournament_id)
        .gte("date", today);
      const { data: ticks } = await supabase.from("availability")
        .select("slot_id")
        .in("slot_id", (slots ?? []).map((s) => s.id));
      const counts = new Map<string, number>();
      for (const t of ticks ?? []) {
        counts.set(t.slot_id, (counts.get(t.slot_id) ?? 0) + 1);
      }
      const orderable = (slots ?? [])
        .filter((s) => (counts.get(s.id) ?? 0) >= tournament.min_players)
        .sort((a, b) =>
          a.date === b.date
            ? a.time.localeCompare(b.time)
            : a.date.localeCompare(b.date)
        );

      // "čt 23.4. 17:30 + 19:00 · so 25.4. 10:00"
      const byDay = new Map<string, string[]>();
      for (const s of orderable) {
        byDay.set(s.date, [...(byDay.get(s.date) ?? []), timeLabel(s.time)]);
      }
      const summary = [...byDay.entries()]
        .map(([date, times]) => `${dayLabel(date)} ${times.join(" + ")}`)
        .join(" · ");
      const n = orderable.length;
      const body = n <= 1
        ? `${summary} už má dost hráčů (min. ${tournament.min_players}). ` +
          "Navrhni objednávku!"
        : `${n} ${n < 5 ? "termíny mají" : "termínů má"} dost hráčů: ` +
          `${summary}. Navrhni objednávku!`;

      await sendToTokens(
        await teamTokens("threshold", [record.user_id as string],
          tournament.team_id as string | undefined),
        `${tournament.name}: dá se objednat!`,
        body,
        {
          kind: "threshold",
          tournament_id: slot.tournament_id as string,
        },
        `threshold-${slot.tournament_id}`,
      );
      return;
    }
  }
}

Deno.serve(async (request) => {
  // Deployed with --no-verify-jwt (DB triggers can't mint JWTs); instead the
  // triggers send a shared secret header checked against the WEBHOOK_SECRET
  // Supabase secret. See supabase/migrations/0003_webhooks.sql.
  const secret = Deno.env.get("WEBHOOK_SECRET");
  if (secret && request.headers.get("x-webhook-secret") !== secret) {
    return new Response("unauthorized", { status: 401 });
  }
  try {
    const payload = await request.json() as WebhookPayload;
    await handle(payload);
    return new Response("ok");
  } catch (error) {
    console.error("notify failed:", error);
    return new Response(`error: ${error}`, { status: 500 });
  }
});
