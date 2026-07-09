// radar — scheduled tournament radar.
//
// Runs on a pg_cron schedule (twice a day). Scrapes public tournament listings
// and, for every tournament not yet in tournament_radar, inserts a row. That
// INSERT fires notify_tournament_radar → the notify function → a push to
// opted-in members. This function only discovers/records; it never sends.
//
// Sources:
//   - turnajekuzelky.cz  — the ČKA reservation system; has /turnaj/N detail
//     links and a rich card list.
//   - kuzelky.cz/turnaje — the ČKA site's "Pozvánky na turnaje" table; a
//     broader list, but only PDF invitations (no per-tournament detail page).
//     (kkmoravskaslavia has no listing page at all, so it can't be a source.)
//
// Cross-source dedup: the two sites share no id, so the same tournament can
// appear on both. We match fuzzily by dedup_key = "starts_on|ends_on|NxMHS"
// (dates + discipline). A row whose key was already seen is recorded with
// suppressed=true so the notify trigger skips it.

import { createClient } from "jsr:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

type RadarEntry = {
  source: string;
  externalId: string;
  name: string;
  url: string;
  discipline: string | null; // normalized "NxMHS" token, or null
  startsOn: string | null; // YYYY-MM-DD
  endsOn: string | null;
};

// "4×120 HS", "2x120 hodů" → "4x120HS" / "2x120HS"; null if no NxM token.
function disciplineToken(raw: string): string | null {
  const m = raw.replace(/×/g, "x").match(/(\d+)\s*x\s*(\d+)/i);
  return m ? `${m[1]}x${m[2]}HS` : null;
}

// dedup_key across sources: same dates + discipline ⇒ same tournament.
function dedupKey(e: RadarEntry): string | null {
  if (!e.startsOn || !e.endsOn || !e.discipline) return null;
  return `${e.startsOn}|${e.endsOn}|${e.discipline}`;
}

// ---------------------------------------------------------------------------
// turnajekuzelky.cz
// ---------------------------------------------------------------------------

export function parseTurnajeKuzelky(html: string): RadarEntry[] {
  const entries: RadarEntry[] = [];
  const blocks = html.split(
    /<div class="card shadow-sm border-0 h-100 tournament-card-/,
  );
  for (const block of blocks.slice(1)) {
    if (!block.startsWith("pending")) continue;
    const id = block.match(/\/turnaj\/(\d+)/)?.[1];
    if (!id) continue;
    const name = (block.match(/card-title[^>]*>\s*([\s\S]*?)\s*<\//)?.[1] ?? "")
      .replace(/<[^>]+>/g, "").trim() || "Turnaj";
    const disc = disciplineToken(block.match(/(\d+x\d+HS)/)?.[1] ?? "");
    const d = block.match(
      /(\d{1,2})\.(\d{1,2})\.(\d{4})\s*[-–]\s*(\d{1,2})\.(\d{1,2})\.(\d{4})/,
    );
    const iso = (dd: string, mm: string, yy: string) =>
      `${yy}-${mm.padStart(2, "0")}-${dd.padStart(2, "0")}`;
    entries.push({
      source: "turnajekuzelky",
      externalId: id,
      name,
      url: `https://turnajekuzelky.cz/turnaj/${id}`,
      discipline: disc,
      startsOn: d ? iso(d[1], d[2], d[3]) : null,
      endsOn: d ? iso(d[4], d[5], d[6]) : null,
    });
  }
  return entries;
}

// ---------------------------------------------------------------------------
// kuzelky.cz/turnaje — "Pozvánky na turnaje" table
// ---------------------------------------------------------------------------

function unescapeHtml(s: string): string {
  return s
    .replace(/&nbsp;/g, " ").replace(/&ndash;/g, "–").replace(/&times;/g, "×")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)));
}

// Dates on kuzelky.cz omit the year ("17. 7. – 31. 7."). Assume the current
// year, rolling to next year when the month is already behind us — so a
// January listing seen in December resolves to next year.
function resolveDate(
  day: number,
  month: number,
  refYear: number,
  refMonth: number,
): string {
  const year = month < refMonth - 6 ? refYear + 1 : refYear;
  return `${year}-${String(month).padStart(2, "0")}-${
    String(day).padStart(2, "0")
  }`;
}

export function parseKuzelky(html: string, now: Date): RadarEntry[] {
  // The invitations table starts at the "Pozvánky na turnaje" heading.
  const start = html.indexOf("Pozvánky na turnaje");
  if (start < 0) return [];
  const tableMatch = html.slice(start).match(/<table[\s\S]*?<\/table>/);
  if (!tableMatch) return [];
  const rows = tableMatch[0].match(/<tr[\s\S]*?<\/tr>/g) ?? [];

  const refYear = now.getUTCFullYear();
  const refMonth = now.getUTCMonth() + 1;
  const entries: RadarEntry[] = [];
  for (const row of rows.slice(1)) { // skip header
    const cells = (row.match(/<td[\s\S]*?<\/td>/g) ?? [])
      .map((td) => unescapeHtml(td.replace(/<[^>]+>/g, "")).trim());
    if (cells.length < 3) continue;
    const [term, venue, disc] = cells;
    const doc = row.match(/href="([^"]+\.(?:pdf|doc)[^"]*)"/i)?.[1];

    const dm = term.match(
      /(\d{1,2})\.\s*(\d{1,2})\.\s*[-–]\s*(\d{1,2})\.\s*(\d{1,2})\./,
    );
    const startsOn = dm
      ? resolveDate(Number(dm[1]), Number(dm[2]), refYear, refMonth)
      : null;
    const endsOn = dm
      ? resolveDate(Number(dm[3]), Number(dm[4]), refYear, refMonth)
      : null;

    // No stable id — use the invitation doc path (unique & stable), else a
    // hash of venue+discipline+term.
    const externalId = doc ??
      `${venue}|${disc}|${term}`.replace(/\s+/g, "_").slice(0, 120);

    // Invitation hrefs are relative to the /turnaje/ page (e.g.
    // "pozvanky/26/x.pdf" → /turnaje/pozvanky/26/x.pdf), not to the site root.
    const docUrl = doc == null
      ? "https://www.kuzelky.cz/turnaje/"
      : /^https?:\/\//.test(doc)
      ? doc
      : doc.startsWith("/")
      ? `https://www.kuzelky.cz${doc}`
      : `https://www.kuzelky.cz/turnaje/${doc}`;

    entries.push({
      source: "kuzelky",
      externalId,
      name: `${venue} — ${disc}`,
      url: docUrl,
      discipline: disciplineToken(disc),
      startsOn,
      endsOn,
    });
  }
  return entries;
}

async function fetchText(url: string, decode?: "cp1250"): Promise<string> {
  const res = await fetch(url, {
    headers: { "User-Agent": "Mozilla/5.0 (radar bot; Termínátor)" },
  });
  if (!res.ok) throw new Error(`fetch ${url} failed: ${res.status}`);
  if (decode === "cp1250") {
    const buf = new Uint8Array(await res.arrayBuffer());
    return new TextDecoder("windows-1250").decode(buf);
  }
  return await res.text();
}

// ---------------------------------------------------------------------------
// kkmoravskaslavia (mkware) — no listing page; walked by ?idt=N.
// ---------------------------------------------------------------------------

const MKWARE_URL = (id: number) =>
  `https://kkmoravskaslavia.cz/mkware/turnaj-tjsokolmistrin.php?idt=${id}`;
// How many consecutive empty ids to tolerate before deciding we've reached the
// end (organizers may skip an id).
const MKWARE_GAP_TOLERANCE = 3;
// Hard cap per run, so a bug can't walk forever.
const MKWARE_MAX_PROBE = 30;

/** Parses one mkware detail page; null when the id has no tournament. */
function parseMkwareDetail(html: string, id: number): RadarEntry | null {
  const h2 = html.match(/<h2[^>]*>([\s\S]*?)<\/h2>/);
  const name = h2 ? h2[1].replace(/<[^>]+>/g, "").trim() : "";
  const dateIds = [...html.matchAll(/id="(\d{4}-\d{2}-\d{2})-/g)].map((m) =>
    m[1]
  );
  // Valid only if it has a title AND a start grid.
  if (!name || dateIds.length === 0) return null;

  dateIds.sort();
  const disc = disciplineToken(
    html.match(/turnaj\s+\w+\s+na\s+(\d+)\s*HS/i)?.[0] ??
      html.match(/(\d+x\d+HS)/)?.[1] ?? "",
  );
  return {
    source: "mkware",
    externalId: String(id),
    name,
    url: MKWARE_URL(id),
    discipline: disc,
    startsOn: dateIds[0],
    endsOn: dateIds[dateIds.length - 1],
  };
}

/** Walks idt upward from the stored cursor; returns new tournaments found. */
async function scanMkware(): Promise<RadarEntry[]> {
  const { data: cursor } = await supabase
    .from("radar_cursor")
    .select("last_id")
    .eq("source", "mkware")
    .maybeSingle();
  const lastId = cursor?.last_id ?? 0;
  if (lastId === 0) return []; // unseeded → don't crawl the back-catalogue

  const found: RadarEntry[] = [];
  let gap = 0;
  let highestValid = lastId;
  for (let step = 1; step <= MKWARE_MAX_PROBE; step++) {
    const id = lastId + step;
    let html: string;
    try {
      html = await fetchText(MKWARE_URL(id));
    } catch {
      break; // network hiccup: stop, try again next run
    }
    const entry = parseMkwareDetail(html, id);
    if (entry) {
      found.push(entry);
      highestValid = id;
      gap = 0;
    } else if (++gap >= MKWARE_GAP_TOLERANCE) {
      break;
    }
  }

  // Advance the cursor to the highest valid id we saw, so we don't re-probe it.
  if (highestValid > lastId) {
    await supabase.from("radar_cursor").update({ last_id: highestValid })
      .eq("source", "mkware");
  }
  return found;
}

async function run(): Promise<{ scanned: number; added: number }> {
  const now = new Date();
  const [tkHtml, kzHtml, mkware] = await Promise.all([
    fetchText("https://turnajekuzelky.cz/"),
    fetchText("https://www.kuzelky.cz/turnaje/", "cp1250"),
    scanMkware(),
  ]);
  const entries = [
    ...parseTurnajeKuzelky(tkHtml),
    ...parseKuzelky(kzHtml, now),
    ...mkware,
  ];

  // Already-known per source (exact) and every dedup_key ever seen (fuzzy).
  const { data: existing } = await supabase
    .from("tournament_radar")
    .select("source, external_id, dedup_key");
  const seenExact = new Set(
    (existing ?? []).map((r) => `${r.source}|${r.external_id}`),
  );
  const seenKeys = new Set(
    (existing ?? []).map((r) => r.dedup_key).filter(Boolean) as string[],
  );

  let added = 0;
  for (const e of entries) {
    if (seenExact.has(`${e.source}|${e.externalId}`)) continue;
    seenExact.add(`${e.source}|${e.externalId}`);

    const key = dedupKey(e);
    // Suppress (record but don't notify) if this tournament was already seen
    // via any source. Newly-seen keys notify and join the seen set.
    const suppressed = key !== null && seenKeys.has(key);
    if (key !== null) seenKeys.add(key);

    const { error } = await supabase.from("tournament_radar").insert({
      source: e.source,
      external_id: e.externalId,
      name: e.name,
      url: e.url,
      discipline: e.discipline,
      starts_on: e.startsOn,
      ends_on: e.endsOn,
      dedup_key: key,
      suppressed,
    });
    if (error) throw new Error(`insert ${e.externalId}: ${error.message}`);
    if (!suppressed) added++;
  }
  return { scanned: entries.length, added };
}

Deno.serve(async (request) => {
  const secret = Deno.env.get("WEBHOOK_SECRET");
  if (secret && request.headers.get("x-webhook-secret") !== secret) {
    return new Response("unauthorized", { status: 401 });
  }
  try {
    return new Response(JSON.stringify(await run()), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("radar failed:", error);
    return new Response(`error: ${error}`, { status: 500 });
  }
});
