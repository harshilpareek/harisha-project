-- ============================================================
--  Harisha — Supabase schema (v3)
--
--  A private, two-person date planner. Exactly two accounts can
--  ever exist: yours and your partner's. That limit is enforced by
--  a trigger on auth.users, so it holds even if someone finds the
--  signup endpoint directly.
--
--  Run this in your Supabase project:
--    Dashboard -> SQL Editor -> New query -> paste -> Run
--
--  >>> BEFORE YOU RUN IT: edit the two email addresses in the
--  >>> "WHO IS ALLOWED IN" block below. Nothing else needs changing.
--
--  Safe to re-run — every statement is idempotent.
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- The couple. There is exactly one, with a fixed id so both
-- accounts land in it automatically — no invite codes needed.
-- ------------------------------------------------------------
create table if not exists public.couples (
  id            uuid primary key default gen_random_uuid(),
  invite_code   text unique,
  city          text,
  region        text,
  lat           double precision,
  lng           double precision,
  last_sweep_at timestamptz,
  created_at    timestamptz not null default now()
);

insert into public.couples (id, invite_code)
values ('00000000-0000-0000-0000-00000000da7e', 'HARISHA')
on conflict (id) do nothing;

create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  couple_id    uuid references public.couples(id),
  color        text,
  created_at   timestamptz not null default now()
);

-- ============================================================
--  WHO IS ALLOWED IN  <<< EDIT THE TWO EMAILS BELOW
--
--  Only these addresses can ever hold an account. Everything else
--  is rejected at the database level. `color` sets that person's
--  accent through the whole app: 'indigo' or 'rose'.
-- ============================================================
create table if not exists public.allowed_people (
  email        text primary key,
  display_name text not null,
  color        text not null default 'indigo',
  couple_id    uuid not null references public.couples(id)
);

insert into public.allowed_people (email, display_name, color, couple_id) values
  ('harshil@example.com', 'Harshil', 'indigo', '00000000-0000-0000-0000-00000000da7e'),
  ('isha@example.com',    'Isha',    'rose',   '00000000-0000-0000-0000-00000000da7e')
on conflict (email) do update
  set display_name = excluded.display_name,
      color        = excluded.color,
      couple_id    = excluded.couple_id;

-- ------------------------------------------------------------
-- The gate: reject any signup that isn't on the list, and set up
-- the profile automatically for the two who are.
-- ------------------------------------------------------------
create or replace function public.enforce_allowlist()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  person public.allowed_people;
begin
  select * into person
    from public.allowed_people
   where lower(email) = lower(new.email);

  if not found then
    raise exception 'This site is private. Only the two of us can sign in.'
      using errcode = 'check_violation';
  end if;

  insert into public.profiles (id, display_name, couple_id, color)
    values (new.id, person.display_name, person.couple_id, person.color)
  on conflict (id) do update
    set display_name = excluded.display_name,
        couple_id    = excluded.couple_id,
        color        = excluded.color;

  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.enforce_allowlist();

-- ------------------------------------------------------------
-- Ideas discovered from Reddit / blogs
-- ------------------------------------------------------------
create table if not exists public.discovered_ideas (
  id           uuid primary key default gen_random_uuid(),
  couple_id    uuid not null references public.couples(id) on delete cascade,
  title        text not null,
  blurb        text,
  source       text,
  source_label text,
  source_url   text,
  vibe         text,
  budget       int,
  setting      text,
  time_of_day  text,
  city         text,
  score        int default 0,
  created_at   timestamptz not null default now()
);

create unique index if not exists discovered_ideas_dedupe on public.discovered_ideas(couple_id, source_url);
create index if not exists discovered_ideas_couple_idx on public.discovered_ideas(couple_id, created_at desc);

-- ------------------------------------------------------------
-- Private votes
-- ------------------------------------------------------------
create table if not exists public.reactions (
  id         uuid primary key default gen_random_uuid(),
  couple_id  uuid not null references public.couples(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  idea_key   text not null,
  idea_title text not null,
  idea_blurb text,
  idea_meta  jsonb,
  reaction   text not null check (reaction in ('yes','maybe','pass')),
  created_at timestamptz not null default now(),
  unique (user_id, idea_key)
);
create index if not exists reactions_couple_idx on public.reactions(couple_id, idea_key);

-- ------------------------------------------------------------
-- The locked-in date + the log of ones you've done
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
alter table public.allowed_people   enable row level security;
alter table public.discovered_ideas enable row level security;
alter table public.reactions        enable row level security;
alter table public.plans            enable row level security;
alter table public.saved_ideas      enable row level security;

create or replace function public.my_couple_id()
returns uuid language sql stable security definer set search_path = public as $$
  select couple_id from public.profiles where id = auth.uid();
$$;

-- allowed_people is never readable from the browser. The login screen
-- gets names from config.js instead, so nobody's email is exposed.
drop policy if exists "nobody reads the allowlist" on public.allowed_people;

drop policy if exists "read couple profiles" on public.profiles;
create policy "read couple profiles" on public.profiles for select
  using (id = auth.uid() or couple_id = public.my_couple_id());
drop policy if exists "update own profile" on public.profiles;
create policy "update own profile" on public.profiles for update
  using (id = auth.uid());

drop policy if exists "read own couple" on public.couples;
create policy "read own couple" on public.couples for select
  using (id = public.my_couple_id());
drop policy if exists "update own couple" on public.couples;
create policy "update own couple" on public.couples for update
  using (id = public.my_couple_id());

drop policy if exists "read couple finds" on public.discovered_ideas;
create policy "read couple finds" on public.discovered_ideas for select
  using (couple_id = public.my_couple_id());
drop policy if exists "insert couple finds" on public.discovered_ideas;
create policy "insert couple finds" on public.discovered_ideas for insert
  with check (couple_id = public.my_couple_id());
drop policy if exists "delete couple finds" on public.discovered_ideas;
create policy "delete couple finds" on public.discovered_ideas for delete
  using (couple_id = public.my_couple_id());

-- Votes are private: you can only ever read rows you wrote.
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

-- Make sure the signed-in user has a profile (the signup trigger
-- normally handles this; this covers accounts made before it existed).
create or replace function public.bootstrap_profile(p_name text default null, p_color text default null)
returns public.profiles language plpgsql security definer set search_path = public as $$
declare
  prof   public.profiles;
  person public.allowed_people;
begin
  select * into prof from public.profiles where id = auth.uid();
  if found then return prof; end if;

  select * into person from public.allowed_people
   where lower(email) = lower(coalesce(auth.email(), ''));
  if not found then
    raise exception 'This account is not on the guest list.';
  end if;

  insert into public.profiles (id, display_name, couple_id, color)
    values (auth.uid(), person.display_name, person.couple_id, person.color)
    returning * into prof;
  return prof;
end; $$;

-- THE REVEAL: only ideas you have BOTH voted on.
create or replace function public.get_consensus()
returns table (
  idea_key text, idea_title text, idea_blurb text, idea_meta jsonb,
  my_reaction text, their_reaction text, their_name text, decided_at timestamptz
)
language plpgsql stable security definer set search_path = public as $$
declare
  cid uuid;
  me  uuid := auth.uid();
begin
  select couple_id into cid from public.profiles where id = me;
  if cid is null then return; end if;
  return query
    select mine.idea_key, mine.idea_title, mine.idea_blurb, mine.idea_meta,
           mine.reaction, theirs.reaction,
           coalesce(p.display_name, 'your partner'),
           greatest(mine.created_at, theirs.created_at)
      from public.reactions mine
      join public.reactions theirs
        on theirs.idea_key = mine.idea_key
       and theirs.couple_id = mine.couple_id
       and theirs.user_id <> mine.user_id
      left join public.profiles p on p.id = theirs.user_id
     where mine.couple_id = cid and mine.user_id = me
     order by greatest(mine.created_at, theirs.created_at) desc;
end; $$;

-- Ideas they've judged that you haven't. Returns the idea, never their answer.
create or replace function public.pending_for_me()
returns table (idea_key text, idea_title text, idea_blurb text, idea_meta jsonb)
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
     where theirs.couple_id = cid and theirs.user_id <> me
       and not exists (select 1 from public.reactions mine
                        where mine.user_id = me and mine.idea_key = theirs.idea_key);
end; $$;

-- Counts only, no answers.
create or replace function public.vote_progress()
returns table (my_votes int, their_votes int, both_voted int, waiting_on_me int, their_name text)
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

grant execute on function public.my_couple_id()                to authenticated;
grant execute on function public.bootstrap_profile(text, text) to authenticated;
grant execute on function public.get_consensus()               to authenticated;
grant execute on function public.pending_for_me()              to authenticated;
grant execute on function public.vote_progress()               to authenticated;

-- ============================================================
--  OPTIONAL: sweep for new ideas every 6 hours.
--  Needs pg_cron + pg_net (Database -> Extensions).
-- ============================================================
-- create extension if not exists pg_cron;
-- create extension if not exists pg_net;
--
-- select cron.schedule('harisha-sweep', '0 */6 * * *', $cron$
--   select net.http_post(
--     url     := 'https://YOUR-PROJECT-REF.supabase.co/functions/v1/discover-dates',
--     headers := '{"Content-Type":"application/json","Authorization":"Bearer YOUR-SERVICE-ROLE-KEY"}'::jsonb,
--     body    := '{"all_couples": true}'::jsonb
--   );
-- $cron$);
