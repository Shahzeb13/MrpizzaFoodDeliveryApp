-- ═══════════════════════════════════════════════════════════════════════════
-- Saved dishes ("My Favourites") per customer account.
--
-- The heart toggle used to live only in memory, so a customer's saved pizzas
-- were gone after a restart and leaked into the next account signed in on a
-- shared phone. This table makes them a property of the account instead, which
-- also means they follow the customer to another device.
--
-- One row per customer per menu item, so a double tap on the heart cannot
-- create duplicates.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.favorites (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  menu_item_id uuid not null references public.menu_items(id) on delete cascade,
  created_at   timestamptz not null default now(),
  unique (user_id, menu_item_id)
);

comment on table public.favorites is
  'Menu items a customer has hearted. Scoped to the account, not the device.';

-- The only query pattern is "this customer's favourites"; the primary key on
-- (user_id, menu_item_id) does not serve it because user_id is not leading in
-- a form PostgREST can seek without scanning.
create index if not exists favorites_user_id_idx on public.favorites(user_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- Row Level Security.
--
-- The publishable key ships inside the APK, so RLS is the only thing standing
-- between a modified client and everybody else's saved dishes. A customer may
-- read, add and remove their own rows and nobody else's.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.favorites enable row level security;

drop policy if exists "favorites own rows" on public.favorites;
create policy "favorites own rows"
  on public.favorites
  for all
  to authenticated
  using      (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
