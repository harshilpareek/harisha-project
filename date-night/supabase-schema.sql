-- ============================================================
--  Date Deck — Supabase schema
--  Run this ONCE in your Supabase project:
--    Dashboard → SQL Editor → New query → paste → Run.
--  It creates the tables, row-level security, and two helper
--  functions the app calls (bootstrap_profile, join_couple).
-- ============================================================

create extension if not exists pgcrypto;

-- A "couple" is the shared space two accounts link into.
create table if not exists public.couples (
  id          uuid primary key default gen_random_uuid(),
  invite_code text unique not null default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 6)),
  created_at  timestamptz not null default now()
);

-- One profile per auth user, pointing at the couple they belong to.
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  couple_id    uuid references public.couples(id),
  created_at   timestamptz not null default now()
);

-- Saved date ideas, shared across the couple.
create table if not exists public.saved_ideas (
  id         uuid primary key default gen_random_uuid(),
  couple_id  uuid references public.couples(id) on delete cascade,
  title      text not null,
  blurb      text,
  meta       jsonb,
  status     text not null default 'saved',   -- 'saved' | 'done'
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  done_at    timestamptz
);

create index if not exists saved_ideas_couple_idx on public.saved_ideas(couple_id);

-- ---------- Row-level security ----------
alter table public.couples     enable row level security;
alter table public.profiles    enable row level security;
alter table public.saved_ideas enable row level security;

-- Helper: the couple_id of the current user (SECURITY DEFINER avoids RLS recursion).
create or replace function public.my_couple_id()
returns uuid language sql stable security definer set search_path = public as $$
  select couple_id from public.profiles where id = auth.uid();
$$;

-- profiles: you can read your own row and your partner's; you can only write your own.
drop policy if exists "read couple profiles" on public.profiles;
create policy "read couple profiles" on public.profiles for select
  using (id = auth.uid() or couple_id = public.my_couple_id());
drop policy if exists "insert own profile" on public.profiles;
create policy "insert own profile" on public.profiles for insert
  with check (id = auth.uid());
drop policy if exists "update own profile" on public.profiles;
create policy "update own profile" on public.profiles for update
  using (id = auth.uid());

-- couples: readable only by its members.
drop policy if exists "read own couple" on public.couples;
create policy "read own couple" on public.couples for select
  using (id = public.my_couple_id());

-- saved_ideas: fully scoped to your couple.
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

-- ---------- Helper functions the app calls ----------

-- Ensure the signed-in user has a profile and a couple; returns the profile row.
create or replace function public.bootstrap_profile(p_name text default null)
returns public.profiles language plpgsql security definer set search_path = public as $$
declare
  prof       public.profiles;
  new_couple uuid;
begin
  select * into prof from public.profiles where id = auth.uid();
  if not found then
    insert into public.couples default values returning id into new_couple;
    insert into public.profiles(id, display_name, couple_id)
      values (auth.uid(), coalesce(nullif(p_name, ''), split_part(auth.email(), '@', 1)), new_couple)
      returning * into prof;
  elsif prof.couple_id is null then
    insert into public.couples default values returning id into new_couple;
    update public.profiles set couple_id = new_couple where id = auth.uid() returning * into prof;
  elsif p_name is not null and coalesce(prof.display_name, '') = '' then
    update public.profiles set display_name = p_name where id = auth.uid() returning * into prof;
  end if;
  return prof;
end; $$;

-- Link into a partner's couple using their invite code.
create or replace function public.join_couple(p_code text)
returns public.profiles language plpgsql security definer set search_path = public as $$
declare
  target uuid;
  prof   public.profiles;
begin
  select id into target from public.couples where invite_code = upper(trim(p_code));
  if target is null then
    raise exception 'That invite code did not match any couple.';
  end if;
  update public.profiles set couple_id = target where id = auth.uid() returning * into prof;
  return prof;
end; $$;

grant execute on function public.my_couple_id()          to authenticated;
grant execute on function public.bootstrap_profile(text) to authenticated;
grant execute on function public.join_couple(text)       to authenticated;
