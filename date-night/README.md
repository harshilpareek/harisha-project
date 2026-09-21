# Harisha 💞

A private date planner for two. You each get a hand of ideas, vote **yes / maybe
/ pass** in secret, and only see each other's answers once you've *both* judged
the same idea. Whatever you both say yes to becomes a match — pick one and it's
locked in as your next date.

A scout runs in the background, sweeping Reddit threads and local blogs for
unusual date ideas near you, so the deck keeps getting fresher.

---

## How it works

| | |
|---|---|
| **Your hand** | 7 ideas at a time. Yes / Maybe / Pass. Nobody sees your calls. |
| **Smart order** | Your hand leads with ideas your partner already voted on — so you converge fast — without ever revealing *how* they voted. |
| **The reveal** | Double-yes = **match**. Yes+maybe = **worth a talk**. Both appear only after you've both voted. |
| **Taste profile** | Your votes build a private profile (vibe affinity, budget lean, homebody vs. out) that weights which ideas you get shown next. |
| **The scout** | Sweeps Reddit + blogs for ideas near your city, classifies them, and drops them into your hand. |
| **The plan** | Lock in one match, give it a date, then mark it done — it moves to your shared log. |

### Blind voting is enforced by the database, not the UI

`reactions` has a row-level security policy that only lets you read **your own
rows**. Your partner's votes reach you through `get_consensus()`, which returns
a pair only when *both* of you have voted on it. So even poking at the API
directly won't show you their answers early.

---

## Two ways to run it

### 1. Local mode — "pass the phone" (zero setup)
Open the page and go. Both perspectives live on one device; tap the **H / I**
switcher in the header to hand over, and a curtain drops so the next person
doesn't see the previous screen. Everything saves in that browser.

Great for trying the whole flow in about two minutes. No live scouting (that
needs a server) — you'll see clearly-marked sample finds instead.

### 2. Backend mode — real accounts, real scouting
Separate logins on separate phones, true enforced-blind voting, synced matches,
and the live Reddit/blog scout.

---

## Backend setup

### Step 1 — Create the database
1. Make a project at [supabase.com](https://supabase.com) (free tier is plenty).
2. **SQL Editor → New query**, paste all of
   [`supabase-schema.sql`](./supabase-schema.sql), **Run**.
   It's idempotent — safe to re-run whenever the schema changes.

### Step 2 — Point the app at it
From **Settings → API** copy your **Project URL** and **anon public** key, then
either:
- copy [`config.example.js`](./config.example.js) to `config.js` and fill it in, **or**
- open the app → **☰ → Connect a backend** and paste them there.

### Step 3 — Sign up and link
You each **Sign up** with your own email. Then one of you shares the invite code
from **☰**, and the other enters it. Votes you made before linking come with you.

> During setup it's easier to turn off **Authentication → Providers → Email →
> Confirm email** so you can sign in immediately.

### Step 4 — Deploy the scout
This is what makes the "search Reddit and blogs" part real. It runs server-side
because browsers can't fetch Reddit directly (CORS).

```bash
npm install -g supabase
supabase login
supabase link --project-ref YOUR-PROJECT-REF
supabase functions deploy discover-dates

# optional — unlocks blog results alongside Reddit
supabase secrets set BRAVE_API_KEY=your-brave-search-key
```

Then in the app: **Finds → Change** to set your city (or tap **Use my current
location**), and hit **Sweep for new ideas**.

### Step 5 — Make it periodic (optional)
The bottom of `supabase-schema.sql` has a commented-out `pg_cron` block that
sweeps every 6 hours. Uncomment it, fill in your project ref and service-role
key, and run it. Without this, the sweep runs whenever you tap the button.

---

## What the scout actually does

Post titles on Reddit are usually the *question* ("unique date ideas in
Austin?"). The good stuff is in the replies — so `discover-dates`:

1. searches your city's subreddit plus general date-idea searches,
2. opens the best threads and reads the **top comments**,
3. throws out the junk (one-word replies, links, "came here to say this"),
4. turns each surviving comment into a title + blurb,
5. classifies vibe / budget / setting / time by keyword,
6. de-dupes against what you already have and files the rest.

Blogs come from the Brave Search API if you set `BRAVE_API_KEY` (free tier is
~2,000 queries/month; a 6-hourly sweep uses a fraction of that).

**Caveat:** Reddit rate-limits unauthenticated traffic and occasionally returns
nothing. The function handles that gracefully — a sweep that finds nothing just
reports zero rather than failing.

---

## Host it (GitHub Pages)

**Settings → Pages → Deploy from a branch**, pick `main` and `/ (root)`. Your
app lands at:

```
https://harshilpareek.github.io/harisha-project/date-night/
```

`config.js` is git-ignored, so if you host publicly use the in-app
**Connect a backend** screen rather than committing your keys.

---

## Files

| Path | What it is |
|------|-----------|
| `index.html` | The entire app — UI, deck, voting, consensus, taste profiles. |
| `supabase-schema.sql` | Tables, row-level security, and the reveal functions. Run once. |
| `supabase/functions/discover-dates/index.ts` | The Reddit + blog scout. |
| `config.example.js` | Template for your keys → copy to `config.js`. |

## Add your own ideas

In `index.html`, find `DECK = [ … ]`:

```js
{ t:"Title of the date", b:"A sentence or two describing it.",
  v:"romantic", budget:1, setting:"out", time:"evening", em:"🌹" },
```

- `v`: `cozy` · `adventurous` · `romantic` · `playful` · `foodie` · `cultured` · `outdoorsy` · `spontaneous`
- `budget`: `0` free · `1` $ · `2` $$ · `3` $$$
- `setting`: `home` · `out` · `outdoors` — `time`: `day` · `evening` · `late`

## Privacy

Local mode keeps everything in your browser. Backend mode keeps everything in
**your own** Supabase project, where row-level security scopes each couple's
data to them — and each person's raw votes to that person alone.
