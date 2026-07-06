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

async function sendToTokens(
  tokens: { userId: string; token: string }[],
  title: string,
  body: string,
) {
  if (tokens.length === 0) return;
  const accessToken = await getAccessToken();
  const url =
    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

  await Promise.all(tokens.map(async ({ userId, token }) => {
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
          android: { priority: "HIGH" },
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

/** All approved members' tokens, minus excluded user ids. */
async function teamTokens(
  exclude: (string | null | undefined)[] = [],
): Promise<{ userId: string; token: string }[]> {
  const { data, error } = await supabase
    .from("profiles")
    .select("id, fcm_token")
    .eq("status", "approved")
    .not("fcm_token", "is", null);
  if (error) throw error;
  const excluded = new Set(exclude.filter(Boolean));
  return (data ?? [])
    .filter((p) => !excluded.has(p.id))
    .map((p) => ({ userId: p.id, token: p.fcm_token as string }));
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

async function tournamentName(id: unknown): Promise<string> {
  const { data } = await supabase.from("tournaments").select("name")
    .eq("id", id).single();
  return (data?.name as string) ?? "turnaj";
}

async function handle(payload: WebhookPayload) {
  const record = payload.record ?? {};

  switch (payload.table) {
    case "profiles": {
      if (payload.type !== "INSERT" || record.status !== "pending") return;
      await sendToTokens(
        await teamTokens([record.id as string]),
        "Nový člen čeká na schválení",
        `${record.display_name} se chce přidat. Schval ho v záložce Tým.`,
      );
      return;
    }

    case "tournaments": {
      if (payload.type !== "INSERT") return;
      await sendToTokens(
        await teamTokens([record.created_by as string]),
        "Nový turnaj 🎳",
        `${record.name} — odklikej si termíny!`,
      );
      return;
    }

    case "orders": {
      const status = record.status as string;
      const oldStatus = payload.old_record?.status as string | undefined;
      const name = await tournamentName(record.tournament_id);
      if (payload.type === "INSERT" && status === "proposed") {
        await sendToTokens(
          await teamTokens([record.created_by as string]),
          `Návrh: ${name}`,
          "Beru / Nemůžu / Radši jiný den — hlasuj v aplikaci.",
        );
      } else if (
        status === "ordered" &&
        (payload.type === "INSERT" || oldStatus === "proposed")
      ) {
        await sendToTokens(
          await teamTokens([record.created_by as string]),
          `Objednáno: ${name}`,
          "Termín je objednaný — přidej se, dokud je místo!",
        );
      } else if (
        payload.type === "UPDATE" && status === "cancelled" &&
        oldStatus !== "cancelled"
      ) {
        await sendToTokens(
          await teamTokens([]),
          `Zrušeno: ${name}`,
          "Návrh/objednávka byla zrušena.",
        );
      }
      return;
    }

    case "messages": {
      if (payload.type !== "INSERT") return;
      const tournamentId = record.tournament_id as string;
      const day = record.day as string | null;
      const name = await tournamentName(tournamentId);

      // Muted users for this chat.
      let mutesQuery = supabase.from("chat_mutes").select("user_id")
        .eq("tournament_id", tournamentId);
      mutesQuery = day === null
        ? mutesQuery.is("day", null)
        : mutesQuery.eq("day", day);
      const { data: mutes } = await mutesQuery;

      const { data: author } = await supabase.from("profiles")
        .select("display_name").eq("id", record.user_id).single();

      const title = day === null
        ? `${name}`
        : `${name} — ${dayLabel(day)}`;
      await sendToTokens(
        await teamTokens([
          record.user_id as string,
          ...(mutes ?? []).map((m) => m.user_id as string),
        ]),
        title,
        `${author?.display_name ?? "?"}: ${record.body}`,
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
        supabase.from("tournaments").select("name, min_players")
          .eq("id", slot.tournament_id).single(),
      ]);
      if (!tournament || (count ?? 0) < tournament.min_players) return;

      // Dedup guard: only the writer that flips the flag sends the push.
      const { data: flipped } = await supabase.from("slots")
        .update({ threshold_notified_at: new Date().toISOString() })
        .eq("id", slotId)
        .is("threshold_notified_at", null)
        .select("id");
      if (!flipped || flipped.length === 0) return;

      await sendToTokens(
        await teamTokens([]),
        `${tournament.name}: dá se objednat!`,
        `${dayLabel(slot.date)} ${timeLabel(slot.time)} už má ${count} hráčů ` +
          `(min. ${tournament.min_players}). Navrhni objednávku!`,
      );
      return;
    }
  }
}

Deno.serve(async (request) => {
  try {
    const payload = await request.json() as WebhookPayload;
    await handle(payload);
    return new Response("ok");
  } catch (error) {
    console.error("notify failed:", error);
    return new Response(`error: ${error}`, { status: 500 });
  }
});
