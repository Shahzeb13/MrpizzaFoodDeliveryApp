-- addresses table + RLS for MrPizza
-- Run in Supabase SQL Editor.

create table if not exists public.addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  label text not null,
  address_line text not null,
  latitude double precision,
  longitude double precision,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.addresses enable row level security;

create policy "own addresses insert"
  on public.addresses for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "own addresses select"
  on public.addresses for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "own addresses update"
  on public.addresses for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "own addresses delete"
  on public.addresses for delete
  to authenticated
  using ((select auth.uid()) = user_id);

-- index for the common lookup path
create index if not exists addresses_user_id_idx
  on public.addresses (user_id);