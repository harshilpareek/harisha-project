# Date Deck 💞

A private date-idea generator for two. Tap the vibes you're feeling, **deal a
card**, save the keepers, and (once you set up accounts) **sync your saved deck
between both your phones**.

It's a single static page — no build step, no server to run. Add a free
[Supabase](https://supabase.com) backend when you want real logins and syncing.

---

## Two ways to run it

### 1. Local mode (works instantly, no setup)
Just open `index.html` — or the hosted page — and start drawing. Set your names
from the **☰** menu. Everything you save is stored **on that device**.
Great for trying it out; not shared between phones.

### 2. Real accounts + sync (recommended for the two of you)
Add a Supabase backend so you each sign in with your own email and your saved
deck stays in sync. ~5 minutes, one time.

#### Setup steps

1. **Create a project** at [supabase.com](https://supabase.com) (the free tier
   is plenty). Wait for it to finish provisioning.

2. **Create the database.** In your project: **SQL Editor → New query**, paste
   the entire contents of [`supabase-schema.sql`](./supabase-schema.sql), and
   click **Run**. This makes the tables, security rules, and helper functions.

3. **Add your keys.** In Supabase go to **Settings → API** and copy:
   - **Project URL** (looks like `https://xxxx.supabase.co`)
   - **anon public** key (safe for the browser — your data is protected by the
     row-level security from step 2)

   Then either:
   - **Self-hosting:** copy [`config.example.js`](./config.example.js) to
     `config.js` and paste the two values in, **or**
   - **From the app:** open **☰ → Connect a backend** and paste them there
     (stored only in that browser).

4. **Sign in on both phones.** You each **Sign up** with your own email
   (confirm via the email Supabase sends), then **link up**: one of you shares
   the invite code from **☰**, the other enters it under *"join their code."*
   Now your saved deck is shared. 🎉

> **Tip:** In Supabase, under **Authentication → Providers → Email**, you can
> turn *"Confirm email"* off during setup if you'd rather skip the confirmation
> step while testing.

---

## Host it (GitHub Pages)

This repo already contains everything. To publish:

1. Push to GitHub (already done if you're reading this on GitHub).
2. Create `date-night/config.js` with your keys **only if** you want the backend
   baked in — otherwise skip it and use the in-app **Connect a backend** screen.
   *(GitHub Pages is public, so anyone could read a committed `config.js`. The
   anon key is browser-safe, but linking accounts is passcode-based, so prefer
   the in-app entry if you'd rather not publish the key.)*
3. In the repo: **Settings → Pages → Build from branch**, pick your branch and
   root, save.
4. Visit `https://<your-username>.github.io/<repo>/date-night/`.

---

## Files

| File | What it is |
|------|------------|
| `index.html` | The whole app — UI, the date deck, and all logic. Edit the `DECK` array near the top of the `<script>` to add your own ideas. |
| `supabase-schema.sql` | Run once in Supabase to create the database. |
| `config.example.js` | Template for your keys → copy to `config.js`. |

## Add your own date ideas

Open `index.html`, find the `DECK = [ … ]` array, and add entries like:

```js
{ t:"Title of the date", b:"One or two sentences describing it.",
  v:"romantic", budget:1, setting:"out", time:"evening", em:"🌹",
  up:"An optional 'level up' tip." },
```

- `v` (vibe): `cozy` · `adventurous` · `romantic` · `playful` · `foodie` · `cultured` · `outdoorsy` · `spontaneous`
- `budget`: `0` free · `1` $ · `2` $$ · `3` $$$
- `setting`: `home` · `out` · `outdoors`
- `time`: `day` · `evening` · `late`

## Privacy

In local mode, nothing leaves the device. With the backend, your data lives in
**your own** Supabase project and row-level security keeps each couple's deck
private to them.
