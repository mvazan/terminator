// Google Calendar API — sdílené mezi calendar-oauth-callback (propojení účtu
// a založení kalendáře) a notify (průběžný sync jobů `calendar_sync`).
//
// Scope: calendar.app.created — všechno tady se dotýká VÝHRADNĚ sekundárního
// kalendáře „Termínátor", který si appka sama založila. Na ostatní kalendáře
// uživatele nevidíme a vidět nechceme.
//
// Vyžaduje secrets: GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET.

const GOOGLE_CLIENT_ID = Deno.env.get("GOOGLE_CLIENT_ID") ?? "";
const GOOGLE_CLIENT_SECRET = Deno.env.get("GOOGLE_CLIENT_SECRET") ?? "";

// Přepsatelné jen kvůli testům proti fake Googlu; v produkci se nenastavují.
const CALENDAR_API = Deno.env.get("GOOGLE_CALENDAR_API") ??
  "https://www.googleapis.com/calendar/v3";
const TOKEN_ENDPOINT = Deno.env.get("GOOGLE_TOKEN_ENDPOINT") ??
  "https://oauth2.googleapis.com/token";

export const CALENDAR_SUMMARY = "Termínátor";
export const CALENDAR_TIMEZONE = "Europe/Prague";

/** Uživatel odvolal přístup (nebo token vypršel v Testing režimu consent
 * screenu po 7 dnech) — propojení je mrtvé, nemá smysl to zkoušet znovu. */
export class GoogleAuthError extends Error {
  constructor(readonly code: "invalid_grant" | "other", message: string) {
    super(message);
    this.name = "GoogleAuthError";
  }
}

/** Refresh token -> krátkodobý access token. Necachujeme napříč joby: tokeny
 * jsou per-uživatel a jedna dávka jobů může míchat víc lidí. */
export async function refreshAccessToken(refreshToken: string): Promise<string> {
  const response = await fetch(TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: GOOGLE_CLIENT_ID,
      client_secret: GOOGLE_CLIENT_SECRET,
      refresh_token: refreshToken,
      grant_type: "refresh_token",
    }),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new GoogleAuthError(
      text.includes("invalid_grant") ? "invalid_grant" : "other",
      `token refresh failed: ${text}`,
    );
  }
  return (await response.json()).access_token as string;
}

/** Výměna authorization code za tokeny (jen callback EF). */
export async function exchangeCode(
  code: string,
  redirectUri: string,
): Promise<{ accessToken: string; refreshToken?: string; idToken?: string }> {
  const response = await fetch(TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: GOOGLE_CLIENT_ID,
      client_secret: GOOGLE_CLIENT_SECRET,
      redirect_uri: redirectUri,
      grant_type: "authorization_code",
    }),
  });
  if (!response.ok) {
    throw new Error(`code exchange failed: ${await response.text()}`);
  }
  const json = await response.json();
  return {
    accessToken: json.access_token,
    refreshToken: json.refresh_token,
    idToken: json.id_token,
  };
}

/** E-mail propojeného účtu z id_tokenu (scope `email`) — jen pro zobrazení
 * v nastavení. Podpis neověřujeme: token přišel přímo z googleapis.com přes
 * HTTPS v odpovědi na náš vlastní požadavek, ne od klienta. */
export function emailFromIdToken(idToken?: string): string | null {
  if (!idToken) return null;
  try {
    const payload = idToken.split(".")[1];
    if (!payload) return null;
    const json = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    return (JSON.parse(json).email as string) ?? null;
  } catch {
    return null;
  }
}

/** Kalendář „Termínátor", který appka v tomhle účtu už dřív založila —
 * nebo null. Scope calendar.app.created vrací v calendarList jen kalendáře
 * vytvořené touhle appkou, takže shoda podle názvu je bezpečná. Používá se
 * při (re-)propojení: založit druhý kalendář vedle starého by uživateli
 * zdvojilo všechny starty v překryvném zobrazení. */
export async function findAppCalendar(
  accessToken: string,
): Promise<string | null> {
  try {
    const response = await fetch(
      `${CALENDAR_API}/users/me/calendarList?minAccessRole=owner`,
      { headers: { Authorization: `Bearer ${accessToken}` } },
    );
    if (!response.ok) {
      console.error(`calendarList.list ${response.status}: ` +
        `${await response.text()}`);
      return null; // radši založit nový než shodit propojení
    }
    const items = (await response.json()).items as
      | { id: string; summary?: string }[]
      | undefined;
    return items?.find((c) => c.summary === CALENDAR_SUMMARY)?.id ?? null;
  } catch (error) {
    console.error("calendarList.list failed (ignored):", error);
    return null;
  }
}

/** Založí sekundární kalendář a vrátí jeho id. Bez připomínek — ty si
 * uživatel řídí sám v Nastavení (job `calendar_reminders`, 0029); čerstvý
 * kalendář z API žádné defaultReminders nemá, což je i chtěný výchozí stav. */
export async function createSecondaryCalendar(
  accessToken: string,
): Promise<string> {
  const response = await fetch(`${CALENDAR_API}/calendars`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      summary: CALENDAR_SUMMARY,
      description: "Tvoje starty z appky Termínátor.",
      timeZone: CALENDAR_TIMEZONE,
    }),
  });
  if (!response.ok) {
    throw new Error(`calendar create failed: ${await response.text()}`);
  }
  return (await response.json()).id as string;
}

/** Propíše preferenci jako defaultReminders kalendáře (calendarList —
 * per-uživatelské nastavení; události je dědí, i ty už založené). */
export async function setDefaultReminders(
  accessToken: string,
  calendarId: string,
  minutes: number[],
): Promise<WriteResult> {
  const response = await fetch(
    `${CALENDAR_API}/users/me/calendarList/${encodeURIComponent(calendarId)}`,
    {
      method: "PATCH",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        defaultReminders: minutes.map((m) => ({ method: "popup", minutes: m })),
      }),
    },
  );
  if (response.ok) return "ok";
  console.error(
    `defaultReminders PATCH ${response.status}: ${await response.text()}`,
  );
  return classify(response.status);
}

// ---------------------------------------------------------------------------
// Události
// ---------------------------------------------------------------------------

const B32HEX = "0123456789abcdefghijklmnopqrstuv";

function base32hex(bytes: Uint8Array): string {
  let bits = 0;
  let value = 0;
  let out = "";
  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += B32HEX[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += B32HEX[(value << (5 - bits)) & 31];
  return out;
}

/** Deterministické id události z (uživatel, slot): stejný start = stejné id,
 * takže upsert i mazání jsou idempotentní a nepotřebujeme mapovací tabulku.
 * Calendar API chce 5–1024 znaků z abecedy base32hex [a-v0-9]. */
export async function eventIdFor(
  userId: string,
  slotId: string,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${userId}:${slotId}`),
  );
  return base32hex(new Uint8Array(digest)).slice(0, 32);
}

/** Délka startu podle disciplíny (minuty). Držet v souladu s Discipline
 * v lib/domain/models.dart — seznam už se jednou rozšiřoval (0006). */
export function durationMinutes(discipline: string | null): number {
  switch (discipline) {
    case "40HS":
      return 45;
    case "60HS":
      return 75;
    case "100HS":
      return 120;
    case "120HS":
      return 135;
    case "180HS":
      return 180;
    default:
      return 120;
  }
}

/** Naivní lokální čas „YYYY-MM-DDTHH:MM:SS" + posun o minuty, BEZ počítání
 * UTC offsetu: letní/zimní čas vyřeší Google podle timeZone: Europe/Prague.
 * Kdybychom offset počítali sami, půlku roku bychom se mýlili o hodinu. */
export function localDateTime(
  date: string,
  time: string,
  addMinutes = 0,
): string {
  const [h, m] = time.split(":").map(Number);
  const total = h * 60 + m + addMinutes;
  const dayShift = Math.floor(total / (24 * 60));
  const minuteOfDay = ((total % (24 * 60)) + 24 * 60) % (24 * 60);

  let day = date;
  if (dayShift !== 0) {
    // Posun data přes UTC půlnoc — datum je tu jen kalendářní, ne okamžik.
    const shifted = new Date(`${date}T00:00:00Z`);
    shifted.setUTCDate(shifted.getUTCDate() + dayShift);
    day = shifted.toISOString().slice(0, 10);
  }
  const hh = String(Math.floor(minuteOfDay / 60)).padStart(2, "0");
  const mm = String(minuteOfDay % 60).padStart(2, "0");
  return `${day}T${hh}:${mm}:00`;
}

export type CalendarEvent = {
  summary: string;
  location?: string;
  description?: string;
  /** „YYYY-MM-DDTHH:MM:SS" v Europe/Prague. */
  start: string;
  end: string;
};

export type WriteResult = "ok" | "auth" | "gone" | "retry";

function classify(status: number): WriteResult {
  if (status === 401) return "auth";
  if (status === 404 || status === 410) return "gone";
  return "retry"; // 403 (kvóta), 429, 5xx, cokoli nečekaného
}

/** Založí nebo přepíše událost pod deterministickým id.
 * PUT na neexistující id NEZALOŽÍ (404) — proto fallback na POST s vlastním
 * id; 409 znamená, že tam smazaná událost s tím id je, a PUT ji vzkřísí
 * (status: "confirmed"). */
export async function upsertEvent(
  accessToken: string,
  calendarId: string,
  eventId: string,
  event: CalendarEvent,
): Promise<WriteResult> {
  const body = JSON.stringify({
    id: eventId,
    status: "confirmed",
    summary: event.summary,
    location: event.location || undefined,
    description: event.description || undefined,
    start: { dateTime: event.start, timeZone: CALENDAR_TIMEZONE },
    end: { dateTime: event.end, timeZone: CALENDAR_TIMEZONE },
  });
  const headers = {
    Authorization: `Bearer ${accessToken}`,
    "Content-Type": "application/json",
  };
  const eventUrl = `${CALENDAR_API}/calendars/${
    encodeURIComponent(calendarId)
  }/events/${eventId}`;

  const put = await fetch(eventUrl, { method: "PUT", headers, body });
  if (put.ok) return "ok";
  if (put.status !== 404) {
    console.error(`event PUT ${put.status}: ${await put.text()}`);
    return classify(put.status);
  }
  // 404 = událost (nebo kalendář) neexistuje. Zkusíme založit.
  const post = await fetch(
    `${CALENDAR_API}/calendars/${encodeURIComponent(calendarId)}/events`,
    { method: "POST", headers, body },
  );
  if (post.ok) return "ok";
  if (post.status === 409) {
    // Smazaná událost s tímhle id tam pořád je — PUT ji vzkřísí.
    const revive = await fetch(eventUrl, { method: "PUT", headers, body });
    if (revive.ok) return "ok";
    console.error(`event revive ${revive.status}: ${await revive.text()}`);
    return classify(revive.status);
  }
  console.error(`event POST ${post.status}: ${await post.text()}`);
  // 404 i tady = kalendář je pryč (uživatel ho smazal v Google Calendar).
  return classify(post.status);
}

/** Smaže událost. Když už tam není (404/410), je hotovo — mazání je
 * idempotentní: job mohl vzniknout dřív, než se událost vůbec založila. */
export async function deleteEvent(
  accessToken: string,
  calendarId: string,
  eventId: string,
): Promise<WriteResult> {
  const response = await fetch(
    `${CALENDAR_API}/calendars/${
      encodeURIComponent(calendarId)
    }/events/${eventId}`,
    { method: "DELETE", headers: { Authorization: `Bearer ${accessToken}` } },
  );
  if (response.ok || response.status === 404 || response.status === 410) {
    return "ok";
  }
  console.error(`event DELETE ${response.status}: ${await response.text()}`);
  return classify(response.status);
}
