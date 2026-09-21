-- ============================================================
--  Harisha — Supabase schema (v2)
--
--  Run this in your Supabase project:
--    Dashboard -> SQL Editor -> New query -> paste -> Run.
--
--  Safe to re-run: every statement is idempotent, so running it
--  again after an update just adds what's missing.
--
--  What it sets up:
--    couples / profiles      - the two of you, linked by invite code
--    discovered_ideas        - date ideas swept from Reddit & blogs
--    reactions               - your PRIVATE yes/maybe/pass votes
--    plans                   - the date you've locked in next
--    saved_ideas             - your log of dates you've actually done
--
--  Privacy note: `reactions` is readable ONLY by the person who
--  wrote the row. Your partner's votes are revealed to you through
--  get_consensus(), and only for ideas you have BOTH voted on.
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- Core: couples + profiles
-- ------------------------------------------------------------
create table if not exists public.couples (
  id          uuid primary key default gen_random_uuid(),
  invite_code text unique not null default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 6)),
  created_at  timestamptz not null default now()
);

-- v2: where you are, so discovery knows what to search for
alter table public.couples add column if not exists city              text;
alter table public.couples add column if not exists region            text;
alter table public.couples add column if not exists lat               double precision;
alter table public.couples add column if not exists lng               double precision;
alter table public.couples add column if not exists last_sweep_at     timestamptz;

create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  couple_id    uuid references public.couples(id),
  created_at   timestamptz not null default now()
);

-- v2: each person gets their own accent color for their perspective
alter table public.profiles add column if not exists color text;

-- ------------------------------------------------------------
-- v2: ideas discovered from Reddit / blogs
-- ------------------------------------------------------------
create table if not exists public.discovered_ideas (
  id           uuid primary key default gen_random_uuid(),
  couple_id    uuid not null references public.couples(id) on delete cascade,
  title        text not null,
  blurb        text,
  source       text,               -- 'reddit' | 'blog'
  source_label text,               -- e.g. 'r/austin'
  source_url   text,
  vibe         text,
  budget       int,
  setting      text,
  time_of_day  text,
  city         text,
  score        int  default 0,     -- upvotes / relevance, for ranking
  created_at   timestamptz not null default now()
);

create unique index if not exists discovered_ideas_dedupe
  on public.discovered_ideas(couple_id, source_url);
create index if not exists discovered_ideas_couple_idx
  on public.discovered_ideas(couple_id, created_at desc);

-- ------------------------------------------------------------
-- v2: private reactions (the "anonymous form")
-- ------------------------------------------------------------
create table if not exists public.reactions (
  id         uuid primary key default gen_random_uuid(),
  couple_id  uuid not null references public.couples(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  idea_key   text not null,        -- 'deck:<slug>' or 'found:<uuid>'
  idea_title text not null,
  idea_blurb text,
  idea_meta  jsonb,
  reaction   text not null check (reaction in ('yes','maybe','pass')),
  created_at timestamptz not null default now(),
  unique (user_id, idea_key)
);

create index if not exists reactions_couple_idx on public.reactions(couple_id, idea_key);

-- ------------------------------------------------------------
-- v2: the date you've locked in
-- ------------------------------------------------------------
create table if not exists public.plans (
  id            uuid primary key default gen_random_uuid(),
  couple_id     uuid not null references public.couples(id) on delete cascade,
  idea_key      text,
  title         text not null,
  blurb         text,
  meta          jsonb,
  scheduled_for date,
  status        text not null default 'planned' check (status in ('planned','done','cancelled')),
  created_by    uuid references auth.users(id),
  created_at    timestamptz not null default now()
);

create index if not exists plans_couple_idx on public.plans(couple_id, created_at desc);

-- ------------------------------------------------------------
-- The log of dates you've actually been on
-- ------------------------------------------------------------
create table if not exists public.saved_ideas (
  id         uuid primary key default gen_random_uuid(),
  couple_id  uuid references public.couples(id) on delete cascade,
  title      text not null,
  blurb      text,
  meta       jsonb,
  status     text not null default 'saved',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  done_at    timestamptz
);

create index if not exists saved_ideas_couple_idx on public.saved_ideas(couple_id);

-- ============================================================
--  Row-level security
-- ============================================================
alter table public.couples          enable row level security;
alter table public.profiles         enable row level security;
alter table public.discovered_ideas enable row level security;
alter table public.reactions        enable row level security;
alter table public.plans            enable row level security;
alter table public.saved_ideas      enable row level security;

-- Helper: the couple_id of the current user.
-- SECURITY DEFINER so it doesn't recurse through profiles' own RLS.
create or replace function public.my_couple_id()
returns uuid language sql stable security definer set search_path = public as $$
  select couple_id from public.profiles where id = auth.uid();
$$;

-- profiles: read your own row and your partner's; write only your own.
drop policy if exists "read couple profiles" on public.profiles;
create policy "read couple profiles" on public.profiles for select
  using (id = auth.uid() or couple_id = public.my_couple_id());
drop policy if exists "insert own profile" on public.profiles;
create policy "insert own profile" on public.profiles for insert
  with check (id = auth.uid());
drop policy if exists "update own profile" on public.profiles;
create policy "update own profile" on public.profiles for update
  using (id = auth.uid());

-- couples: readable and updatable by its members.
drop policy if exists "read own couple" on public.couples;
create policy "read own couple" on public.couples for select
  using (id = public.my_couple_id());
drop policy if exists "update own couple" on public.couples;
create policy "update own couple" on public.couples for update
  using (id = public.my_couple_id());

-- discovered_ideas: shared across the couple.
drop policy if exists "read couple finds" on public.discovered_ideas;
create policy "read couple finds" on public.discovered_ideas for select
  using (couple_id = public.my_couple_id());
drop policy if exists "insert couple finds" on public.discovered_ideas;
create policy "insert couple finds" on public.discovered_ideas for insert
  with check (couple_id = public.my_couple_id());
drop policy if exists "delete couple finds" on public.discovered_ideas;
create policy "delete couple finds" on public.discovered_ideas for delete
  using (couple_id = public.my_couple_id());

-- reactions: PRIVATE. You can only ever see your own rows.
-- (Your partner's votes reach you only via get_consensus(), below.)
drop policy if exists "read own reactions" on public.reactions;
create policy "read own reactions" on public.reactions for select
  using (user_id = auth.uid());
drop policy if exists "write own reactions" on public.reactions;
create policy "write own reactions" on public.reactions for insert
  with check (user_id = auth.uid() and couple_id = public.my_couple_id());
drop policy if exists "update own reactions" on public.reactions;
create policy "update own reactions" on public.reactions for update
  using (user_id = auth.uid());
drop policy if exists "delete own reactions" on public.reactions;
create policy "delete own reactions" on public.reactions for delete
  using (user_id = auth.uid());

-- plans + saved_ideas: shared across the couple.
drop policy if exists "read couple plans" on public.plans;
create policy "read couple plans" on public.plans for select
  using (couple_id = public.my_couple_id());
drop policy if exists "write couple plans" on public.plans;
create policy "write couple plans" on public.plans for insert
  with check (couple_id = public.my_couple_id());
drop policy if exists "update couple plans" on public.plans;
create policy "update couple plans" on public.plans for update
  using (couple_id = public.my_couple_id());
drop policy if exists "delete couple plans" on public.plans;
create policy "delete couple plans" on public.plans for delete
  using (couple_id = public.my_couple_id());

drop policy if exists "read couple ideas" on public.saved_ideas;
create policy "read couple ideas" on public.saved_ideas for select
  using (couple_id = public.my_couple_id());
drop policy if exists "insert couple ideas" on public.saved_ideas;
create policy "insert couple ideas" on public.saved_ideas for insert
  with check (couple_id = public.my_couple_id() and created_by = auth.uid());
drop policy if exists "update couple ideas" on public.saved_ideas;
create policy "update couple ideas" on public.saved_ideas for update
  using (couple_id = public.my_couple_id());
drop policy if exists "delete couple ideas" on public.saved_ideas;
create policy "delete couple ideas" on public.saved_ideas for delete
  using (couple_id = public.my_couple_id());

-- ============================================================
--  Functions the app calls
-- ============================================================

-- Ensure the signed-in user has a profile and a couple; returns the profile.
create or replace function public.bootstrap_profile(p_name text default null, p_color text default null)
returns public.profiles language plpgsql security definer set search_path = public as $$
declare
  prof       public.profiles;
  new_couple uuid;
begin
  select * into prof from public.profiles where id = auth.uid();
  if not found then
    insert into public.couples default values returning id into new_couple;
    insert into public.profiles(id, display_name, couple_id, color)
      values (auth.uid(), coalesce(nullif(p_name, ''), split_part(auth.email(), '@', 1)), new_couple, p_color)
      returning * into prof;
  else
    if prof.couple_id is null then
      insert into public.couples default values returning id into new_couple;
      update public.profiles set couple_id = new_couple where id = auth.uid() returning * into prof;
    end if;
    if nullif(p_name, '') is not null and coalesce(prof.display_name, '') = '' then
      update public.profiles set display_name = p_name where id = auth.uid() returning * into prof;
    end if;
    if nullif(p_color, '') is not null and coalesce(prof.color, '') = '' then
      update public.profiles set color = p_color where id = auth.uid() returning * into prof;
    end if;
  end if;
  return prof;
end; $$;

-- Link into a partner's couple using their invite code.
-- Moves any reactions/finds you already made into the shared couple.
create or replace function public.join_couple(p_code text)
returns public.profiles language plpgsql security definer set search_path = public as $$
declare
  target uuid;
  mine   uuid;
  prof   public.profiles;
begin
  select couple_id into mine from public.profiles where id = auth.uid();
  select id into target from public.couples where invite_code = upper(trim(p_code));
  if target is null then
    raise exception 'That invite code did not match any couple.';
  end if;
  if target = mine then
    raise exception 'That is your own invite code — share it with your partner instead.';
  end if;

  update public.profiles set couple_id = target where id = auth.uid() returning * into prof;

  -- carry your existing votes over so nothing is lost when you link up
  if mine is not null then
    update public.reactions set couple_id = target where user_id = auth.uid() and couple_id = mine;
    delete from public.couples where id = mine
      and not exists (select 1 from public.profiles where couple_id = mine);
  end if;

  return prof;
end; $$;

-- ------------------------------------------------------------
-- THE REVEAL: ideas you have BOTH voted on, with both answers.
-- This is the only way to learn your partner's vote, and it will
-- not tell you anything about an idea you haven't voted on yourself.
-- ------------------------------------------------------------
create or replace function public.get_consensus()
returns table (
  idea_key       text,
  idea_title     text,
  idea_blurb     text,
  idea_meta      jsonb,
  my_reaction    text,
  their_reaction text,
  their_name     text,
  decided_at     timestamptz
)
language plpgsql stable security definer set search_path = public as $$
declare
  cid uuid;
  me  uuid := auth.uid();
begin
  select couple_id into cid from public.profiles where id = me;
  if cid is null then return; end if;

  return query
    select mine.idea_key,
           mine.idea_title,
           mine.idea_blurb,
           mine.idea_meta,
           mine.reaction,
           theirs.reaction,
           coalesce(p.display_name, 'your partner'),
           greatest(mine.created_at, theirs.created_at)
    from public.reactions mine
    join public.reactions theirs
      on theirs.idea_key  = mine.idea_key
     and theirs.couple_id = mine.couple_id
     and theirs.user_id  <> mine.user_id
    left join public.profiles p on p.id = theirs.user_id
    where mine.couple_id = cid
      and mine.user_id   = me
    order by greatest(mine.created_at, theirs.created_at) desc;
end; $$;

-- ------------------------------------------------------------
-- Ideas your partner has already voted on that you haven't.
-- Returns the IDEA only — never their answer. Used to order your
-- hand so the two of you converge quickly.
-- ------------------------------------------------------------
create or replace function public.pending_for_me()
returns table (
  idea_key   text,
  idea_title text,
  idea_blurb text,
  idea_meta  jsonb
)
language plpgsql stable security definer set search_path = public as $$
declare
  cid uuid;
  me  uuid := auth.uid();
begin
  select couple_id into cid from public.profiles where id = me;
  if cid is null then return; end if;

  return query
    select distinct theirs.idea_key, theirs.idea_title, theirs.idea_blurb, theirs.idea_meta
    from public.reactions theirs
    where theirs.couple_id = cid
      and theirs.user_id  <> me
      and not exists (
        select 1 from public.reactions mine
        where mine.user_id = me and mine.idea_key = theirs.idea_key
      );
end; $$;

-- ------------------------------------------------------------
-- Scoreboard: how far along each of you is. Counts only — no answers.
-- ------------------------------------------------------------
create or replace function public.vote_progress()
returns table (
  my_votes       int,
  their_votes    int,
  both_voted     int,
  waiting_on_me  int,
  their_name     text
)
language plpgsql stable security definer set search_path = public as $$
declare
  cid uuid;
  me  uuid := auth.uid();
begin
  select couple_id into cid from public.profiles where id = me;
  if cid is null then return; end if;

  return query
    select
      (select count(*)::int from public.reactions where couple_id = cid and user_id = me),
      (select count(*)::int from public.reactions where couple_id = cid and user_id <> me),
      (select count(*)::int from public.reactions a
         join public.reactions b on b.idea_key = a.idea_key and b.couple_id = a.couple_id and b.user_id <> a.user_id
        where a.couple_id = cid and a.user_id = me),
      (select count(distinct t.idea_key)::int from public.reactions t
        where t.couple_id = cid and t.user_id <> me
          and not exists (select 1 from public.reactions m where m.user_id = me and m.idea_key = t.idea_key)),
      (select coalesce(max(p.display_name), 'your partner') from public.profiles p
        where p.couple_id = cid and p.id <> me);
end; $$;

grant execute on function public.my_couple_id()                    to authenticated;
grant execute on function public.bootstrap_profile(text, text)     to authenticated;
grant execute on function public.join_couple(text)                 to authenticated;
grant execute on function public.get_consensus()                   to authenticated;
grant execute on function public.pending_for_me()                  to authenticated;
grant execute on function public.vote_progress()                   to authenticated;

-- ============================================================
--  OPTIONAL: run the discovery sweep automatically every 6 hours.
--
--  Requires the pg_cron and pg_net extensions (Database ->
--  Extensions in the dashboard). Replace YOUR-PROJECT-REF and
--  YOUR-SERVICE-ROLE-KEY, then run this block.
--
--  Skip this entirely if you'd rather just hit "Sweep now" in the
--  app — everything works without it.
-- ============================================================
-- create extension if not exists pg_cron;
-- create extension if not exists pg_net;
--
-- select cron.schedule(
--   'harisha-sweep',
--   '0 */6 * * *',
--   $cron$
--     select net.http_post(
--       url     := 'https://YOUR-PROJECT-REF.supabase.co/functions/v1/discover-dates',
--       headers := '{"Content-Type":"application/json","Authorization":"Bearer YOUR-SERVICE-ROLE-KEY"}'::jsonb,
--       body    := '{"all_couples": true}'::jsonb
--     );
--   $cron$
-- );
