// ============================================================
//  Harisha — discover-dates
//
//  A Supabase Edge Function that sweeps the web for unique date
//  ideas near you and files them into `discovered_ideas`.
//
//  Sources
//    1. Reddit (always on, no API key)
//         - searches your city's subreddit + the big date-idea subs
//         - opens the top threads and mines the TOP COMMENTS, which
//           is where the actual ideas are. Post titles are usually
//           just the question ("unique date ideas in Austin?").
//    2. Blogs via Brave Search (optional)
//         - set the BRAVE_API_KEY secret to turn this on.
//           Brave's free tier is ~2,000 queries/month, which is far
//           more than a 6-hourly sweep needs.
//
//  Invoke it either way:
//    - From the app ("Sweep now") with the signed-in user's JWT.
//      It sweeps that user's couple only.
//    - From cron with the service-role key and {"all_couples": true}.
//
//  Deploy:
//    supabase functions deploy discover-dates
//    supabase secrets set BRAVE_API_KEY=...        # optional
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BRAVE_API_KEY = Deno.env.get("BRAVE_API_KEY") ?? "";

// Reddit blocks default/blank agents. Identify politely.
const UA = "harisha-date-finder/1.0 (personal project; contact via github)";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Couple = {
  id: string;
  city: string | null;
  region: string | null;
};

type Candidate = {
  title: string;
  blurb: string;
  source: "reddit" | "blog";
  source_label: string;
  source_url: string;
  score: number;
};

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/* ------------------------------------------------------------
   Classification — cheap keyword heuristics, no LLM needed.
   ------------------------------------------------------------ */
const VIBE_RULES: [string, RegExp][] = [
  ["foodie", /\b(restaurant|food|eat|dinner|brunch|taco|ramen|pizza|bakery|coffee|café|cafe|wine|brewery|distillery|tasting|market|dessert|ice cream)\b/i],
  ["outdoorsy", /\b(hike|hiking|trail|park|lake|river|beach|kayak|canoe|paddle|camp|bike|mountain|waterfall|garden|botanical|sunset|stargaz)\b/i],
  ["cultured", /\b(museum|gallery|art|theater|theatre|play|orchestra|symphony|exhibit|history|historic|bookstore|library|film|cinema|jazz)\b/i],
  ["playful", /\b(arcade|mini golf|minigolf|bowling|karaoke|trivia|game|escape room|axe throw|go.?kart|roller|skating|amusement|carnival)\b/i],
  ["adventurous", /\b(climb|zip line|ziplin|skydiv|surf|rent|road trip|explore|adventure|rafting|horseback|hot air)\b/i],
  ["romantic", /\b(romantic|sunset|candle|rooftop|view|scenic|picnic|stroll|intimate|cozy dinner)\b/i],
  ["cozy", /\b(cozy|at home|home|movie night|blanket|fireplace|bake|board game|puzzle|spa|bath)\b/i],
];

const SETTING_RULES: [string, RegExp][] = [
  ["outdoors", /\b(hike|trail|park|lake|river|beach|kayak|paddle|camp|bike|outdoor|picnic|garden|sunset|stargaz|walk)\b/i],
  ["home", /\b(at home|home|apartment|living room|couch|kitchen|backyard|bake|cook together)\b/i],
];

const TIME_RULES: [string, RegExp][] = [
  ["late", /\b(night|late|midnight|bar|club|karaoke|stargaz|after dark|nightcap)\b/i],
  ["day", /\b(morning|brunch|breakfast|daytime|afternoon|sunrise|matinee)\b/i],
];

function classify(text: string) {
  const vibe = VIBE_RULES.find(([, re]) => re.test(text))?.[0] ?? "spontaneous";
  const setting = SETTING_RULES.find(([, re]) => re.test(text))?.[0] ?? "out";
  const time_of_day = TIME_RULES.find(([, re]) => re.test(text))?.[0] ?? "evening";

  // budget: look for explicit price signals, else guess from the vibe
  let budget = 2;
  if (/\bfree\b|\bno cost\b|\bcosts? nothing\b|\bdoesn'?t cost\b/i.test(text)) budget = 0;
  else if (/\bcheap\b|\bbudget\b|\baffordable\b|\bunder \$?\d{1,2}\b/i.test(text)) budget = 1;
  else if (/\bexpensive\b|\bsplurge\b|\bfancy\b|\bupscale\b|\btasting menu\b|\$\d{3,}/i.test(text)) budget = 3;
  else if (setting === "home" || vibe === "outdoorsy") budget = 1;

  return { vibe, setting, time_of_day, budget };
}

/* ------------------------------------------------------------
   Text cleanup
   ------------------------------------------------------------ */
function cleanText(s: string): string {
  return s
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/\[([^\]]+)\]\((https?:[^)]+)\)/g, "$1")   // markdown links -> text
    .replace(/https?:\/\/\S+/g, "")                      // bare urls
    .replace(/^&gt;.*$/gm, "")                           // quoted replies
    .replace(/[*_~`#>]/g, "")                            // markdown noise
    .replace(/\s+/g, " ")
    .trim();
}

// Turn a comment into a short headline: first sentence, tidied up.
function toTitle(s: string): string {
  let t = (s.split(/(?<=[.!?])\s+/)[0] ?? s).trim();
  t = t.replace(/^(i'?d say|honestly|personally|my go.?to is|try|check out|definitely|you could|maybe)\s+/i, "");
  t = t.replace(/^[-–—•\d.)\s]+/, "");
  if (t.length > 90) t = t.slice(0, 87).replace(/\s+\S*$/, "") + "…";
  if (!t) return "";
  return t.charAt(0).toUpperCase() + t.slice(1);
}

// Junk filter — comments that aren't ideas.
const JUNK = /^(this|same|agreed?|lol|haha|yes|no|thanks?|thank you|came here to say|underrated|following|rip|deleted|removed|\[.*\])$/i;
function looksLikeIdea(s: string): boolean {
  if (s.length < 45 || s.length > 600) return false;
  if (JUNK.test(s.trim())) return false;
  if (/^(edit|update)\s*:/i.test(s)) return false;
  // needs at least one verb-ish/place-ish signal
  return /\b(go|visit|try|walk|hike|take|grab|check|see|eat|drink|ride|rent|book|watch|play|explore|head|spend|climb|catch)\b/i.test(s);
}

/* ------------------------------------------------------------
   Reddit
   ------------------------------------------------------------ */
async function redditJson(url: string): Promise<any | null> {
  try {
    const res = await fetch(url, { headers: { "User-Agent": UA, Accept: "application/json" } });
    if (!res.ok) {
      console.warn(`reddit ${res.status} for ${url}`);
      return null;
    }
    return await res.json();
  } catch (e) {
    console.warn("reddit fetch failed", url, String(e));
    return null;
  }
}

function citySub(city: string): string {
  return city.toLowerCase().replace(/[^a-z]/g, "");
}

async function sweepReddit(city: string, region: string | null): Promise<Candidate[]> {
  const out: Candidate[] = [];
  const sub = citySub(city);
  const place = region ? `${city} ${region}` : city;

  // 1) Find promising threads
  const searches = [
    `https://www.reddit.com/r/${sub}/search.json?q=${encodeURIComponent("date ideas")}&restrict_sr=1&sort=top&t=all&limit=10`,
    `https://www.reddit.com/search.json?q=${encodeURIComponent(`${place} date ideas`)}&sort=top&t=year&limit=10`,
    `https://www.reddit.com/search.json?q=${encodeURIComponent(`${place} unique things to do couples`)}&sort=top&t=year&limit=8`,
  ];

  const threads: { id: string; sub: string; title: string; permalink: string }[] = [];
  for (const url of searches) {
    const json = await redditJson(url);
    const children = json?.data?.children ?? [];
    for (const c of children) {
      const d = c?.data;
      if (!d?.id || !d?.subreddit) continue;
      if (d.over_18) continue;
      if ((d.num_comments ?? 0) < 4) continue;
      if (threads.some((t) => t.id === d.id)) continue;
      threads.push({ id: d.id, sub: d.subreddit, title: d.title ?? "", permalink: d.permalink ?? "" });
    }
    await sleep(700); // be a good citizen
  }

  // 2) Mine the top comments of the best threads
  for (const t of threads.slice(0, 8)) {
    const json = await redditJson(
      `https://www.reddit.com/comments/${t.id}.json?limit=30&sort=top&depth=1`,
    );
    const listing = Array.isArray(json) ? json[1] : null;
    const comments = listing?.data?.children ?? [];

    for (const c of comments) {
      const d = c?.data;
      if (!d || d.stickied || !d.body) continue;
      const score = d.score ?? 0;
      if (score < 3) continue;

      const body = cleanText(d.body);
      if (!looksLikeIdea(body)) continue;

      const title = toTitle(body);
      if (!title || title.length < 12) continue;

      out.push({
        title,
        blurb: body.length > 320 ? body.slice(0, 317).replace(/\s+\S*$/, "") + "…" : body,
        source: "reddit",
        source_label: `r/${t.sub}`,
        source_url: `https://www.reddit.com${d.permalink ?? t.permalink}`,
        score,
      });
    }
    await sleep(700);
  }

  return out;
}

/* ------------------------------------------------------------
   Blogs (Brave Search) — optional
   ------------------------------------------------------------ */
async function sweepBlogs(city: string): Promise<Candidate[]> {
  if (!BRAVE_API_KEY) return [];
  const queries = [
    `unique date ideas in ${city}`,
    `unusual things to do for couples in ${city}`,
  ];
  const out: Candidate[] = [];

  for (const q of queries) {
    try {
      const res = await fetch(
        `https://api.search.brave.com/res/v1/web/search?q=${encodeURIComponent(q)}&count=10&freshness=py`,
        { headers: { Accept: "application/json", "X-Subscription-Token": BRAVE_API_KEY } },
      );
      if (!res.ok) {
        console.warn("brave", res.status);
        continue;
      }
      const json = await res.json();
      for (const r of json?.web?.results ?? []) {
        const desc = cleanText(r.description ?? "");
        if (desc.length < 40) continue;
        let host = "";
        try { host = new URL(r.url).hostname.replace(/^www\./, ""); } catch { /* ignore */ }
        if (/reddit\.com|pinterest\./.test(host)) continue;
        out.push({
          title: toTitle(cleanText(r.title ?? "")) || cleanText(r.title ?? "").slice(0, 80),
          blurb: desc.length > 320 ? desc.slice(0, 317) + "…" : desc,
          source: "blog",
          source_label: host || "blog",
          source_url: r.url,
          score: 5,
        });
      }
    } catch (e) {
      console.warn("brave failed", String(e));
    }
    await sleep(400);
  }
  return out;
}

/* ------------------------------------------------------------
   Sweep one couple
   ------------------------------------------------------------ */
async function sweepCouple(admin: any, couple: Couple) {
  if (!couple.city) return { couple: couple.id, skipped: "no city set", inserted: 0 };

  const [fromReddit, fromBlogs] = await Promise.all([
    sweepReddit(couple.city, couple.region),
    sweepBlogs(couple.city),
  ]);

  // Dedupe by URL, then by near-identical title
  const seenUrl = new Set<string>();
  const seenTitle = new Set<string>();
  const candidates: Candidate[] = [];
  for (const c of [...fromReddit, ...fromBlogs].sort((a, b) => b.score - a.score)) {
    const tk = c.title.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 40);
    if (seenUrl.has(c.source_url) || seenTitle.has(tk)) continue;
    seenUrl.add(c.source_url);
    seenTitle.add(tk);
    candidates.push(c);
  }

  const rows = candidates.slice(0, 60).map((c) => ({
    couple_id: couple.id,
    title: c.title,
    blurb: c.blurb,
    source: c.source,
    source_label: c.source_label,
    source_url: c.source_url,
    city: couple.city,
    score: c.score,
    ...classify(`${c.title} ${c.blurb}`),
  }));

  let inserted = 0;
  if (rows.length) {
    // ignoreDuplicates leans on the (couple_id, source_url) unique index,
    // so re-sweeping is cheap and never creates repeats.
    const { data, error } = await admin
      .from("discovered_ideas")
      .upsert(rows, { onConflict: "couple_id,source_url", ignoreDuplicates: true })
      .select("id");
    if (error) console.error("insert failed", error.message);
    else inserted = data?.length ?? 0;
  }

  await admin.from("couples").update({ last_sweep_at: new Date().toISOString() }).eq("id", couple.id);

  return { couple: couple.id, city: couple.city, found: candidates.length, inserted };
}

/* ------------------------------------------------------------
   HTTP entry point
   ------------------------------------------------------------ */
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const admin = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  try {
    const body = await req.json().catch(() => ({}));
    let couples: Couple[] = [];

    if (body.all_couples) {
      // cron path: sweep everyone who has set an area
      const { data } = await admin
        .from("couples")
        .select("id, city, region")
        .not("city", "is", null);
      couples = data ?? [];
    } else {
      // app path: resolve the caller's couple from their JWT
      const jwt = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
      const { data: userRes } = await admin.auth.getUser(jwt);
      const uid = userRes?.user?.id;
      if (!uid) {
        return new Response(JSON.stringify({ error: "Not signed in." }), {
          status: 401, headers: { ...CORS, "Content-Type": "application/json" },
        });
      }
      const { data: prof } = await admin.from("profiles").select("couple_id").eq("id", uid).single();
      if (!prof?.couple_id) {
        return new Response(JSON.stringify({ error: "No couple found for this account." }), {
          status: 400, headers: { ...CORS, "Content-Type": "application/json" },
        });
      }
      const { data: couple } = await admin
        .from("couples").select("id, city, region").eq("id", prof.couple_id).single();
      if (couple) couples = [couple];

      // let the app override/refresh the area in the same call
      if (body.city) {
        await admin.from("couples").update({
          city: body.city,
          region: body.region ?? null,
          lat: body.lat ?? null,
          lng: body.lng ?? null,
        }).eq("id", prof.couple_id);
        couples = [{ id: prof.couple_id, city: body.city, region: body.region ?? null }];
      }
    }

    const results = [];
    for (const c of couples) results.push(await sweepCouple(admin, c));

    return new Response(JSON.stringify({ ok: true, results }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500, headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
