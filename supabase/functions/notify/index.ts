// notify — the single push-notification Edge Function.
//
// Triggered by Supabase Database Webhooks (see SETUP.md) on:
//   INSERT profiles      -> "new member waiting for approval"
//   INSERT tournaments   -> "new tournament"
//   INSERT orders        -> "new proposal" / "ordered" (direct order)
//   UPDATE orders        -> "ordered" / "cancelled"
//   INSERT messages      -> chat message (skips muted users and the author)
//   INSERT availability  -> threshold check: slot just reached min players
//                           (event-driven; dedup via slots.threshold_notified_at)
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
          notification: { title, body },
          // `channel` also travels in data so the app's foreground handler
          // picks the same channel for its local notification.
          data: { ...data, channel },
          android: {
            priority: "HIGH",
            notification: {
              channel_id: channel,
              ...(tag ? { tag } : {}),
            },
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
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  record: Record<string, unknown> | null;
  old_record: Record<string, unknown> | null;
};

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
      if (isNewProposal) {
        await sendToTokens(
          await teamTokens("proposal",
            [record.created_by as string, ...hiders], teamId),
          `Návrh: ${name}`,
          "Beru / Nemůžu / Radši jiný den — hlasuj v aplikaci.",
          orderData,
        );
      } else if (isOrdered) {
        await sendToTokens(
          await teamTokens("order",
            [record.created_by as string, ...hiders], teamId),
          `Objednáno: ${name}`,
          "Termín je objednaný — přidej se, dokud je místo!",
          orderData,
        );
      } else {
        await sendToTokens(
          await teamTokens("order", hiders, teamId),
          `Zrušeno: ${name}`,
          "Návrh/objednávka byla zrušena.",
          orderData,
        );
      }
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
