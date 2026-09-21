# Harisha 💞

A private date planner built for exactly two people. You each vote on ideas in
secret — **yes / maybe / pass** — and only see each other's answers once you've
*both* judged the same idea. Whatever you both say yes to becomes a match; pick
one and it's locked in as your next date.

A scout runs in the background, sweeping Reddit threads and local blogs for
unusual things to do near you, so the deck keeps getting fresher.

**Live site:** `https://harshilpareek.github.io/harisha-project/`

---

## Only two people can ever sign in

This isn't a UI trick. `supabase-schema.sql` installs a trigger on `auth.users`
that rejects any signup whose email isn't on the allowlist:

```
raise exception 'This site is private. Only the two of us can sign in.'
```

So the site can sit on the public internet — anyone can *find* it, nobody else
can *get in*. The two allowed accounts are pre-paired into the same couple, so
there's no invite code to exchange.

### And your votes stay yours

`reactions` has a row-level security policy that only lets you read **your own
rows**. Your partner's votes reach you through `get_consensus()`, which returns
a pair only when both of you have voted on it. Poking the API directly won't
show you their answers early.

---

## The themes

106 ideas across eight themes, weighted toward the ones you actually use:

| | | |
|---|---|---|
| 🍜 **Food** (18) | 🎲 **Game night** (17) | 🌆 **Going out** (15) |
| 🛋️ **Cozy in** (12) | 🌲 **Outdoors** (12) | 🎭 **Culture** (10) |
| 🧭 **Adventure** (10) | 🌹 **Romance** (12) | |

Food leans into *themed* nights — monochrome dinners, a 1974 menu, a spice
ladder, Chopped with five mystery ingredients. Game night covers board games,
co-op campaigns, arcade bars, and a chess ladder where the loser cooks.

---

## Setup

### 1. Create the database
1. Make a project at [supabase.com](https://supabase.com) (free tier is fine).
2. Open [`supabase-schema.sql`](./supabase-schema.sql) and **edit the two email
   addresses** in the `WHO IS ALLOWED IN` block near the top.
3. **SQL Editor → New query**, paste the whole file, **Run**.
   It's idempotent — safe to re-run any time.

### 2. Create exactly two users
**Authentication → Users → Add user**, twice, using the same two addresses.
Set a password for each. Any other address is rejected by the trigger.

> Also switch off **Authentication → Providers → Email → Enable signups** for
> belt and braces.

### 3. Point the site at your project
Copy [`config.example.js`](./config.example.js) to `config.js`, fill in your
**Project URL** and **anon public** key from **Settings → API**, and **commit
it**.

Committing `config.js` is correct here — the anon key is designed to live in a
browser, and row-level security plus the allowlist are what protect your data.
Never put the `service_role` key in it.

You can also drop your two emails into `config.js` to get a nicer login screen
(two name buttons, password only). Leave them blank to keep your addresses off
a public page and use a normal email + password form instead. Either way the
database enforces the same two accounts.

### 4. Deploy the scout (optional but fun)
This is the part that searches Reddit and blogs. It runs server-side because
browsers can't fetch Reddit directly (CORS).

```bash
npm install -g supabase
supabase login
supabase link --project-ref YOUR-PROJECT-REF
supabase functions deploy discover-dates

supabase secrets set BRAVE_API_KEY=...   # optional, adds blog results
```

Then in the app: **Finds → Change** to set your city (or tap **Use my current
location**) and hit **Sweep for new ideas**.

### 5. Sweep on a schedule (optional)
The bottom of `supabase-schema.sql` has a commented-out `pg_cron` block that
sweeps every 6 hours. Fill in your project ref and service-role key, uncomment,
run.

---

## Hosting

[`.github/workflows/deploy-pages.yml`](../.github/workflows/deploy-pages.yml)
publishes the site on every push to `main`. It uses
`actions/configure-pages` with `enablement: true`, so it switches GitHub Pages
on by itself the first time it runs.

If that step fails (some accounts restrict it), enable it once by hand:
**Settings → Pages → Source: GitHub Actions**, then re-run the workflow.

The `date-night/` folder is published as the site root, so the URL stays clean.

---

## What the scout actually does

Reddit post titles are usually the *question* ("unique date ideas in Austin?").
The good stuff is in the replies — so `discover-dates`:

1. searches your city's subreddit plus general date-idea queries,
2. opens the best threads and reads the **top comments**,
3. drops the junk (one-word replies, bare links, "came here to say this"),
4. turns each surviving comment into a title + blurb,
5. tags it with a theme, budget, setting and time by keyword,
6. de-dupes against what you already have and files the rest.

Every card links back to the comment it came from.

**Caveat:** Reddit rate-limits anonymous traffic and sometimes returns nothing.
A sweep that finds nothing reports zero rather than failing.

---

## Files

| Path | What it is |
|------|-----------|
| `index.html` | The whole app — deck, voting, consensus, taste profiles. |
| `supabase-schema.sql` | Tables, the two-account gate, RLS, reveal functions. |
| `supabase/functions/discover-dates/index.ts` | The Reddit + blog scout. |
| `config.example.js` | Template → copy to `config.js` and commit. |

## Add your own ideas

In `index.html`, find `DECK = [ … ]`:

```js
{ t:"Title of the date", b:"A sentence or two describing it.",
  v:"food", budget:1, setting:"home", time:"evening", em:"🍜" },
```

- `v`: `food` · `games` · `night` · `cozy` · `outdoors` · `culture` · `adventure` · `romance`
- `budget`: `0` free · `1` $ · `2` $$ · `3` $$$
- `setting`: `home` · `out` · `outdoors` — `time`: `day` · `evening` · `late`

## Demo mode

Without a backend (or by tapping **Have a look around**), the site runs entirely
in the browser: both perspectives on one device with a pass-the-phone handoff,
and clearly-labelled sample finds. Nothing syncs — it's there so the thing is
explorable before any setup.
