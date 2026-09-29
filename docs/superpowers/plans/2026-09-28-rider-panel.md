# Rider Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fake rider dashboard with one driven by the real `rider_details` and `rider_assignments` tables, with every status transition enforced by the database.

**Architecture:** Riders read their own assignments through RLS-scoped SELECTs and change nothing directly. All six lifecycle transitions (`assigned → accepted → picked_up → delivered`, plus `declined` and `failed`) go through `SECURITY DEFINER` Postgres functions that validate ownership, guard the current state, and write `orders.status` and `order_status_history` in the same transaction. The delivery contact is snapshotted onto `orders` at checkout so a rider never needs read access to customer profile rows.

**Tech Stack:** Flutter 3 / Dart, Riverpod 2.6 (`flutter_riverpod ^2.5.1`), `supabase_flutter ^2.0.0`, go_router 14, Postgres 17 with RLS, `package:http` `MockClient` for repository tests.

**Spec:** `docs/superpowers/specs/2026-09-28-rider-panel-design.md` — the plan argues from the spec, so read both.

## Global Constraints

- **Never write to the live Supabase project without explicit written permission from the user.** This applies to `apply_migration`, `execute_sql`, and Edge Function deploys. Tasks 1–3 only *write migration files to the repo* and touch no database. Task 4 is the gate.
- Migration files live in `supabase/migrations/` and are named `NNN_snake_case.sql` with a leading timestamp, matching the existing `supabase/addresses_table.sql` location for SQL.
- Every migration must be re-runnable: use `if not exists` / `if exists` and `create or replace` throughout. A migration that fails halfway must not leave the database blocked.
- **`enable row level security` and its policies ship in the same migration file.** Enabling RLS with zero policies locks out every client, including the customer app and the Next.js panel.
- The panel is identified by the existing `public.is_staff()` helper. Do not introduce a second staff-check mechanism, and do not require `service_role`.
- Every transition function is `security definer` + `set search_path = public`, matching the existing `is_staff()` / `is_owner()` pattern.
- Rider and customer Dart code must never read from a table it does not own under RLS. Customer contact details come from the `orders` snapshot columns only.
- Naming is self-documenting (`claimOffer`, `pendingOffersFor`, `payoutRateFor`) — see `AGENTS.md`.
- Test command is `flutter test`; analysis is `flutter analyze`. Both must be clean before any commit.
- Dart tests must never contact Supabase. Inject a `SupabaseClient` built on `MockClient` in repository tests.

## Review Focus

These are the inputs the spec implies but does not spell out. Each has a test in the owning task — do not skip them.

1. **An order placed before the snapshot columns existed** (the 8 rows already in `orders` have `NULL` contact columns). A rider assigned one must see a card that says the contact details are unavailable, never a blank card.
2. **A rider with no `rider_details` row** — `rider@test.com` is in exactly this state today. Expected: a "your rider account is not set up yet" message, not a crash and not an empty dashboard.
3. **Double-tapping Accept or Delivered.** The second tap must be rejected by the function's status guard and surfaced as "this delivery is no longer yours", never applied twice. Enforced in SQL, so it is proven by the rolled-back transaction check in Task 4 Step 5, not by a Dart test.
4. **Tapping Go Available while already holding a job.** Must be refused with a readable message, and `rider_details.status` must stay `on_delivery`. Also proven in Task 4 Step 5.
5. **Riders cannot read `store_settings`** — its only policy is `is_staff()`. Without a rider-readable SELECT policy the payout rate silently reads as 0 and the earnings screen lies. Must either read the real rate or say the rate is unavailable, never show a silent 0. Covered by the "rate is unavailable" test in Task 13.

---

# Phase 1 — Schema and access (no database contact)

### Task 1: Foundation migration file

**Files:**
- Create: `supabase/migrations/20260928090000_rider_panel_foundation.sql`
- Test: manual SQL review only — this task contacts no database and has no automated test

**Interfaces:**
- Consumes: nothing
- Produces: `public.is_staff()`, `public.is_owner()` (re-declared idempotently); widened `rider_assignments_status_check`; `orders.customer_name`, `orders.customer_phone`, `orders.delivery_address`, `orders.delivery_latitude`, `orders.delivery_longitude`; `store_settings.rider_payout_per_delivery`

- [ ] **Step 1: Create the migrations directory if absent**

```bash
Test-Path supabase/migrations
```

If `False`, create it: `New-Item -ItemType Directory -Path supabase/migrations`

- [ ] **Step 2: Write the migration file**

```sql
-- Rider panel foundation.
--
-- Nothing in this file changes access control. It only widens the assignment
-- lifecycle, adds the delivery-contact snapshot, and adds the rider payout rate.
-- RLS and the transition functions arrive in the following migrations.

-- The staff helpers exist only in the live database today; no migration creates
-- them, so rebuilding from migrations would break every policy that calls them.
-- Re-declared idempotently so this repo is the source of truth from now on.
create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from public.admin_users
    where id = (select auth.uid()) and role = 'owner'
  );
$$;

create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
    select 1 from public.admin_users
    where id = (select auth.uid())
  );
$$;

-- 'accepted' and 'declined' are both required by the lifecycle and neither
-- exists today, so a rider accepting a job currently has nowhere to record it.
alter table public.rider_assignments
  drop constraint if exists rider_assignments_status_check;

alter table public.rider_assignments
  add constraint rider_assignments_status_check
  check (status in ('assigned','accepted','picked_up','delivered','declined','failed'));

-- Delivery contact snapshot. A rider cannot read the customer's profiles or
-- addresses row (both are own-rows-only under RLS), so the details are copied
-- onto the order at checkout and read from there.
alter table public.orders
  add column if not exists customer_name    text,
  add column if not exists customer_phone   text,
  add column if not exists delivery_address text,
  add column if not exists delivery_latitude  numeric,
  add column if not exists delivery_longitude numeric;

-- Payout per completed delivery. 250 is a placeholder carried over from the
-- demo screen and must be confirmed by the business before riders are shown
-- earnings. Changing it later is a one-cell update.
alter table public.store_settings
  add column if not exists rider_payout_per_delivery numeric not null default 250;

-- Backfill the orders that already exist, so an old order is still deliverable.
update public.orders o
   set customer_name  = p.full_name,
       customer_phone = p.phone
  from public.profiles p
 where p.id = o.customer_id
   and o.customer_name is null;

update public.orders o
   set delivery_address   = a.address_line,
       delivery_latitude  = a.latitude,
       delivery_longitude = a.longitude
  from public.addresses a
 where a.id = o.address_id
   and o.delivery_address is null;
```

- [ ] **Step 3: Verify the file reads correctly and contains no secret**

```bash
Select-String -Path supabase/migrations/20260928090000_rider_panel_foundation.sql -Pattern "service_role|sb_secret|anon_key"
```

Expected: no matches.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260928090000_rider_panel_foundation.sql
git commit -m "add rider panel foundation migration: helpers, assignment lifecycle, delivery contact snapshot, payout rate"
```

---

### Task 2: Transition functions migration

**Files:**
- Create: `supabase/migrations/20260928091000_rider_transition_functions.sql`
- Test: manual SQL review only — no database contact

**Interfaces:**
- Consumes: the widened `rider_assignments_status_check` and `rider_details` table from Task 1
- Produces: `public.rider_claim_offer(uuid)`, `public.rider_decline_offer(uuid)`, `public.rider_mark_picked_up(uuid)`, `public.rider_complete_delivery(uuid)`, `public.rider_fail_delivery(uuid, text)`, `public.rider_set_availability(text)` — each returning the affected row

- [ ] **Step 1: Write the migration file**

```sql
-- Rider lifecycle transitions.
--
-- These six functions are the ONLY way a rider changes a delivery. The app
-- receives no direct UPDATE grant on rider_assignments, rider_details or
-- orders. Each function:
--   1. proves the row belongs to the signed-in rider,
--   2. locks it FOR UPDATE so two racing taps cannot both win,
--   3. refuses the transition if the current status is not the expected one,
--   4. writes every related row in the same transaction.

create or replace function public.rider_claim_offer(p_assignment_id uuid)
returns public.rider_assignments
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_row public.rider_assignments;
begin
  select * into v_row
    from public.rider_assignments
   where id = p_assignment_id
     and rider_id = (select auth.uid())
   for update;

  if not found then
    raise exception 'Delivery not found, or it is not assigned to you'
      using errcode = 'P0002';
  end if;

  if v_row.status <> 'assigned' then
    raise exception 'This delivery is no longer available'
      using errcode = 'P0002';
  end if;

  update public.rider_assignments
     set status = 'accepted'
   where id = v_row.id
  returning * into v_row;

  update public.rider_details
     set status = 'on_delivery'
   where profile_id = v_row.rider_id;

  return v_row;
end;
$$;

create or replace function public.rider_decline_offer(p_assignment_id uuid)
returns public.rider_assignments
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_row public.rider_assignments;
begin
  select * into v_row
    from public.rider_assignments
   where id = p_assignment_id
     and rider_id = (select auth.uid())
   for update;

  if not found then
    raise exception 'Delivery not found, or it is not assigned to you'
      using errcode = 'P0002';
  end if;

  if v_row.status <> 'assigned' then
    raise exception 'This delivery is no longer available'
      using errcode = 'P0002';
  end if;

  update public.rider_assignments
     set status = 'declined'
   where id = v_row.id
  returning * into v_row;

  update public.rider_details
     set status = 'available'
   where profile_id = v_row.rider_id;

  -- orders.status is deliberately untouched: the order stays claimable so the
  -- panel can assign somebody else.
  return v_row;
end;
$$;

create or replace function public.rider_mark_picked_up(p_assignment_id uuid)
returns public.rider_assignments
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_row public.rider_assignments;
begin
  select * into v_row
    from public.rider_assignments
   where id = p_assignment_id
     and rider_id = (select auth.uid())
   for update;

  if not found then
    raise exception 'Delivery not found, or it is not assigned to you'
      using errcode = 'P0002';
  end if;

  if v_row.status <> 'accepted' then
    raise exception 'Accept this delivery before marking it picked up'
      using errcode = 'P0002';
  end if;

  update public.rider_assignments
     set status      = 'picked_up',
         picked_up_at = now()
   where id = v_row.id
  returning * into v_row;

  update public.orders
     set status = 'out_for_delivery'
   where id = v_row.order_id;

  insert into public.order_status_history (order_id, status, changed_by)
  values (v_row.order_id, 'out_for_delivery', (select auth.uid()));

  return v_row;
end;
$$;

create or replace function public.rider_complete_delivery(p_assignment_id uuid)
returns public.rider_assignments
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_row public.rider_assignments;
begin
  select * into v_row
    from public.rider_assignments
   where id = p_assignment_id
     and rider_id = (select auth.uid())
   for update;

  if not found then
    raise exception 'Delivery not found, or it is not assigned to you'
      using errcode = 'P0002';
  end if;

  if v_row.status <> 'picked_up' then
    raise exception 'Pick this delivery up before marking it delivered'
      using errcode = 'P0002';
  end if;

  update public.rider_assignments
     set status       = 'delivered',
         delivered_at = now()
   where id = v_row.id
  returning * into v_row;

  update public.orders
     set status = 'delivered'
   where id = v_row.order_id;

  insert into public.order_status_history (order_id, status, changed_by)
  values (v_row.order_id, 'delivered', (select auth.uid()));

  update public.rider_details
     set status = 'available'
   where profile_id = v_row.rider_id;

  return v_row;
end;
$$;

create or replace function public.rider_fail_delivery(
  p_assignment_id uuid,
  p_reason        text
)
returns public.rider_assignments
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_row public.rider_assignments;
begin
  select * into v_row
    from public.rider_assignments
   where id = p_assignment_id
     and rider_id = (select auth.uid())
   for update;

  if not found then
    raise exception 'Delivery not found, or it is not assigned to you'
      using errcode = 'P0002';
  end if;

  if v_row.status not in ('accepted', 'picked_up') then
    raise exception 'Only an active delivery can be reported as failed'
      using errcode = 'P0002';
  end if;

  update public.rider_assignments
     set status = 'failed'
   where id = v_row.id
  returning * into v_row;

  -- Hand the order back so the panel can reassign it.
  update public.orders
     set status = 'confirmed'
   where id = v_row.order_id;

  insert into public.order_status_history (order_id, status, changed_by)
  values (v_row.order_id, 'confirmed', (select auth.uid()));

  update public.rider_details
     set status = 'available'
   where profile_id = v_row.rider_id;

  return v_row;
end;
$$;

create or replace function public.rider_set_availability(p_status text)
returns public.rider_details
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_row public.rider_details;
begin
  -- 'on_delivery' is deliberately not settable here. Only the lifecycle
  -- functions may put a rider on delivery, so the status can never disagree
  -- with the assignment the rider actually holds.
  if p_status not in ('offline', 'available') then
    raise exception 'Riders can only go online or offline'
      using errcode = 'P0002';
  end if;

  if not exists (
    select 1 from public.rider_details
    where profile_id = (select auth.uid())
  ) then
    raise exception 'Your rider account is not set up yet'
      using errcode = 'P0002';
  end if;

  if p_status = 'available' and exists (
    select 1 from public.rider_assignments
    where rider_id = (select auth.uid())
      and status in ('accepted', 'picked_up')
  ) then
    raise exception 'Finish your current delivery first'
      using errcode = 'P0002';
  end if;

  update public.rider_details
     set status = p_status
   where profile_id = (select auth.uid())
  returning * into v_row;

  return v_row;
end;
$$;

-- The app talks to these over PostgREST /rpc, so revoke the implicit execute
-- grant from anon and re-give it only to signed-in users.
revoke execute on function public.rider_claim_offer(uuid)      from public;
revoke execute on function public.rider_decline_offer(uuid)    from public;
revoke execute on function public.rider_mark_picked_up(uuid)   from public;
revoke execute on function public.rider_complete_delivery(uuid) from public;
revoke execute on function public.rider_fail_delivery(uuid, text) from public;
revoke execute on function public.rider_set_availability(text) from public;

grant execute on function public.rider_claim_offer(uuid)      to authenticated;
grant execute on function public.rider_decline_offer(uuid)    to authenticated;
grant execute on function public.rider_mark_picked_up(uuid)   to authenticated;
grant execute on function public.rider_complete_delivery(uuid) to authenticated;
grant execute on function public.rider_fail_delivery(uuid, text) to authenticated;
grant execute on function public.rider_set_availability(text) to authenticated;
```

- [ ] **Step 2: Re-read the file and check every function refuses the wrong state**

Confirm by eye that each function has: a `for update` lock, a `not found` guard, and a status guard that raises before any `update`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260928091000_rider_transition_functions.sql
git commit -m "add rider lifecycle transition functions with state guards, row locks and order history writes"
```

---

### Task 3: Row Level Security migration

**Files:**
- Create: `supabase/migrations/20260928092000_rider_rls_policies.sql`
- Test: manual SQL review only — no database contact

**Interfaces:**
- Consumes: `is_staff()` from Task 1, all six functions from Task 2
- Produces: RLS enabled and policied on `orders`, `order_items`, `order_status_history`, `rider_details`, `rider_assignments`, `branches`, `transactions`, `loyalty_ledger`; a rider-readable SELECT policy on `store_settings`

- [ ] **Step 1: Write the migration file**

```sql
-- Row Level Security for the rider-facing tables.
--
-- RLS is currently DISABLED on these tables, so any holder of the publishable
-- key baked into the shipped APK can read and modify every row. Enabling RLS
-- with no policies blocks every client, so each enable ships with its policies
-- in this same file.
--
-- Three audiences:
--   customer — own rows only
--   rider    — own assignments only, no write access at all
--   panel    — is_staff(), exactly as the existing menu/voucher policies do

alter table public.orders              enable row level security;
alter table public.order_items          enable row level security;
alter table public.order_status_history enable row level security;
alter table public.rider_details        enable row level security;
alter table public.rider_assignments    enable row level security;
alter table public.branches             enable row level security;
alter table public.transactions         enable row level security;
alter table public.loyalty_ledger       enable row level security;

-- ---------------------------------------------------------------- orders
drop policy if exists "orders visible to customer rider or staff" on public.orders;
create policy "orders visible to customer rider or staff"
  on public.orders for select to authenticated
  using (
    customer_id = (select auth.uid())
    or public.is_staff()
    or exists (
      select 1
        from public.rider_assignments ra
       where ra.order_id = orders.id
         and ra.rider_id = (select auth.uid())
    )
  );

drop policy if exists "orders customer creates own" on public.orders;
create policy "orders customer creates own"
  on public.orders for insert to authenticated
  with check (customer_id = (select auth.uid()));

-- Riders never update orders directly; the lifecycle functions do it.
drop policy if exists "orders staff updates" on public.orders;
create policy "orders staff updates"
  on public.orders for update to authenticated
  using (public.is_staff())
  with check (public.is_staff());

-- ----------------------------------------------------------- order_items
drop policy if exists "order_items visible with parent order" on public.order_items;
create policy "order_items visible with parent order"
  on public.order_items for select to authenticated
  using (
    exists (
      select 1 from public.orders o
       where o.id = order_items.order_id
    )
  );

drop policy if exists "order_items customer creates on own order" on public.order_items;
create policy "order_items customer creates on own order"
  on public.order_items for insert to authenticated
  with check (
    exists (
      select 1 from public.orders o
       where o.id = order_items.order_id
         and o.customer_id = (select auth.uid())
    )
  );

drop policy if exists "order_items staff writes" on public.order_items;
create policy "order_items staff writes"
  on public.order_items for update to authenticated
  using (public.is_staff())
  with check (public.is_staff());

drop policy if exists "order_items staff deletes" on public.order_items;
create policy "order_items staff deletes"
  on public.order_items for delete to authenticated
  using (public.is_staff());

-- --------------------------------------------------- order_status_history
drop policy if exists "history visible with parent order" on public.order_status_history;
create policy "history visible with parent order"
  on public.order_status_history for select to authenticated
  using (
    exists (
      select 1 from public.orders o
       where o.id = order_status_history.order_id
    )
  );

drop policy if exists "history staff appends" on public.order_status_history;
create policy "history staff appends"
  on public.order_status_history for insert to authenticated
  with check (public.is_staff());

-- ---------------------------------------------------------- rider_details
drop policy if exists "rider sees own detail or staff sees all" on public.rider_details;
create policy "rider sees own detail or staff sees all"
  on public.rider_details for select to authenticated
  using (profile_id = (select auth.uid()) or public.is_staff());

-- Staff create the row when they create the rider account.
drop policy if exists "rider_details staff creates" on public.rider_details;
create policy "rider_details staff creates"
  on public.rider_details for insert to authenticated
  with check (public.is_staff());

-- No rider UPDATE policy on purpose: availability is set through
-- rider_set_availability(), which also refuses the state changes a plain
-- update would allow (e.g. a rider setting themselves to 'on_delivery').
drop policy if exists "rider_details staff deletes" on public.rider_details;
create policy "rider_details staff deletes"
  on public.rider_details for delete to authenticated
  using (public.is_staff());

-- ------------------------------------------------------ rider_assignments
drop policy if exists "rider sees own assignments or staff sees all"
  on public.rider_assignments;
create policy "rider sees own assignments or staff sees all"
  on public.rider_assignments for select to authenticated
  using (rider_id = (select auth.uid()) or public.is_staff());

-- The panel assigns the job; the rider never inserts one.
drop policy if exists "rider_assignments staff inserts" on public.rider_assignments;
create policy "rider_assignments staff inserts"
  on public.rider_assignments for insert to authenticated
  with check (public.is_staff());

-- No rider UPDATE policy: rider_claim_offer / decline / picked_up /
-- complete / fail are the only paths.
drop policy if exists "rider_assignments staff deletes" on public.rider_assignments;
create policy "rider_assignments staff deletes"
  on public.rider_assignments for delete to authenticated
  using (public.is_staff());

-- ------------------------------------------------------------- branches
drop policy if exists "branches readable by everyone" on public.branches;
create policy "branches readable by everyone"
  on public.branches for select to anon, authenticated
  using (true);

drop policy if exists "branches staff writes" on public.branches;
create policy "branches staff writes"
  on public.branches for all to authenticated
  using (public.is_staff())
  with check (public.is_staff());

-- --------------------------------------------------------- transactions
drop policy if exists "transactions visible to payer or staff" on public.transactions;
create policy "transactions visible to payer or staff"
  on public.transactions for select to authenticated
  using (
    public.is_staff()
    or exists (
      select 1 from public.orders o
       where o.id = transactions.order_id
         and o.customer_id = (select auth.uid())
    )
  );

drop policy if exists "transactions staff writes" on public.transactions;
create policy "transactions staff writes"
  on public.transactions for insert to authenticated
  with check (public.is_staff());

drop policy if exists "transactions staff updates" on public.transactions;
create policy "transactions staff updates"
  on public.transactions for update to authenticated
  using (public.is_staff())
  with check (public.is_staff());

-- ------------------------------------------------------- loyalty_ledger
drop policy if exists "loyalty visible to owner or staff" on public.loyalty_ledger;
create policy "loyalty visible to owner or staff"
  on public.loyalty_ledger for select to authenticated
  using (user_id = (select auth.uid()) or public.is_staff());

drop policy if exists "loyalty staff appends" on public.loyalty_ledger;
create policy "loyalty staff appends"
  on public.loyalty_ledger for insert to authenticated
  with check (public.is_staff());

-- ------------------------------------------------------- store_settings
-- store_settings currently has a single ALL policy gated on is_staff(), so a
-- signed-in rider or customer cannot read it at all. Without this SELECT
-- policy the rider payout rate silently reads as 0 and the earnings screen
-- shows a lie. The table holds no secrets (delivery fee, first-order
-- discount, payout rate), so signed-in users may read it; writes still
-- require is_staff() through the pre-existing ALL policy.
drop policy if exists "store_settings readable when signed in" on public.store_settings;
create policy "store_settings readable when signed in"
  on public.store_settings for select to authenticated
  using (true);
```

- [ ] **Step 2: Confirm every `enable row level security` has policies in this file**

```bash
Select-String -Path supabase/migrations/20260928092000_rider_rls_policies.sql -Pattern "enable row level security" | Measure-Object
Select-String -Path supabase/migrations/20260928092000_rider_rls_policies.sql -Pattern "create policy" | Measure-Object
```

Expected: 8 enables and 21 `create policy` statements in one file.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260928092000_rider_rls_policies.sql
git commit -m "enable rls on rider facing tables with customer rider and staff policies, plus a rider readable store_settings"
```

---

### Task 4: GATE — apply the migrations to the live project

**This task writes to the live database. Do not start it without the user saying go in this conversation.**

**Files:**
- Read: `supabase/migrations/*.sql`
- Modify: `supabase/addresses_table.sql` — leave untouched; migrations are a new directory

**Interfaces:**
- Consumes: the three migration files from Tasks 1–3
- Produces: a live database where the rider panel schema and policies exist

- [ ] **Step 1: State exactly what will run, and get explicit approval**

Present the user with the three filenames and the fact that this alters their live database. Do not proceed on an inferred yes.

- [ ] **Step 2: Apply migration 1, then verify before continuing**

Use `supabase_apply_migration` with `project_id: eytsownrsujphibqpimt`.

Then read it back (read-only, no permission needed):

```sql
select column_name, data_type from information_schema.columns
 where table_schema='public' and table_name='orders'
   and column_name in ('customer_name','customer_phone','delivery_address','delivery_latitude','delivery_longitude');

select conname, pg_get_constraintdef(oid) from pg_constraint
 where conrelid='public.rider_assignments'::regclass and conname='rider_assignments_status_check';
```

Expected: 5 columns present; the check allows `accepted` and `declined`.

- [ ] **Step 3: Apply migration 2 and confirm all six functions exist**

```sql
select proname from pg_proc
 join pg_namespace n on n.oid=pronamespace
 where n.nspname='public' and proname like 'rider_%'
 order by proname;
```

Expected: `rider_claim_offer`, `rider_complete_delivery`, `rider_decline_offer`, `rider_fail_delivery`, `rider_mark_picked_up`, `rider_set_availability`.

- [ ] **Step 4: Apply migration 3 and confirm the customer app is not locked out**

```sql
select tablename, policyname, cmd from pg_policies
 where schemaname='public' and tablename='orders' order by policyname;

select relname, relrowsecurity from pg_class c
 join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relname in
   ('orders','order_items','order_status_history','rider_details','rider_assignments','branches','transactions','loyalty_ledger');
```

Expected: `relrowsecurity` true on all 8, and `orders` has the three policies.

- [ ] **Step 5: Prove the two database-level guards actually refuse**

Review Focus items 3 and 4 are enforced in SQL, so they cannot be covered by a
Dart unit test. Verify them here with real calls inside a transaction that is
rolled back, so the database is left untouched. This is a write against the live
project and needs the same permission as the migration itself.

Run each block below with `execute_sql`. `set local role authenticated` makes
`auth.uid()` resolve, and the trailing `rollback` discards everything.

Guard 3 — a second tap on an already-delivered job must be refused, and a rider
may not deliver a job they never picked up:

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub',
  '75944721-332f-4136-94f1-6715c5964e0f', true);
-- pick any assignment belonging to that rider
select public.rider_complete_delivery(
  (select id from public.rider_assignments
    where rider_id = '75944721-332f-4136-94f1-6715c5964e0f'
    limit 1));
rollback;
```

Expected: raises `Pick this delivery up before marking it delivered`. If it
succeeds instead, the status guard in Task 2 is missing and the function is not
safe — fix it before continuing.

Guard 4 — a rider holding a job must not be able to go available:

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub',
  '75944721-332f-4136-94f1-6715c5964e0f', true);
select public.rider_set_availability('available');
rollback;
```

Expected: either raises `Finish your current delivery first`, or raises
`Your rider account is not set up yet` when the rider has no `rider_details` row.
A silent success means the guard is missing.

Also confirm the execute grants are correct — the app must be able to call these,
and `anon` must not:

```sql
select has_function_privilege('anon', 'public.rider_claim_offer(uuid)', 'execute')  as anon_can_claim,
       has_function_privilege('authenticated', 'public.rider_claim_offer(uuid)', 'execute') as rider_can_claim;
```

Expected: `anon_can_claim` false, `rider_can_claim` true.

- [ ] **Step 6: Smoke-test the customer path still works**

Sign in as a customer in the app and place one test order. Confirm checkout completes and `orders` gains a row with the five snapshot columns still `NULL` (they are populated by Task 10, which has not run yet). If checkout fails with a permission error, stop and roll back to the last good migration rather than debugging forward.

- [ ] **Step 7: Record the applied migrations in the repo**

```bash
git status --short
```

Expected: clean. If the Supabase CLI wrote a migration log, commit it.

---

# Phase 2 — Data layer (pure Dart, no database contact)

### Task 5: `RiderAvailability`

**Files:**
- Create: `lib/features/rider/models/rider_availability.dart`
- Test: `test/rider_availability_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `enum RiderAvailability { offline, available, onDelivery }`, `riderAvailabilityFromDatabaseValue(String?)`, `riderAvailabilityToDatabaseValue(RiderAvailability)`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/rider/models/rider_availability.dart';

void main() {
  test('reads the three statuses the database allows', () {
    expect(riderAvailabilityFromDatabaseValue('offline'),
        RiderAvailability.offline);
    expect(riderAvailabilityFromDatabaseValue('available'),
        RiderAvailability.available);
    expect(riderAvailabilityFromDatabaseValue('on_delivery'),
        RiderAvailability.onDelivery);
  });

  test('an unknown or missing status is offline, never available', () {
    expect(riderAvailabilityFromDatabaseValue(null),
        RiderAvailability.offline);
    expect(riderAvailabilityFromDatabaseValue(''), RiderAvailability.offline);
    expect(riderAvailabilityFromDatabaseValue('on-delivery'),
        RiderAvailability.offline);
  });

  test('casing and padding do not change the reading', () {
    expect(riderAvailabilityFromDatabaseValue('  AVAILABLE '),
        RiderAvailability.available);
  });

  test('round trips through the database value', () {
    for (final availability in RiderAvailability.values) {
      expect(
        riderAvailabilityFromDatabaseValue(
            riderAvailabilityToDatabaseValue(availability)),
        availability,
      );
    }
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/rider_availability_test.dart`
Expected: FAIL — the file does not exist.

- [ ] **Step 3: Write the implementation**

```dart
/// The `rider_details.status` values the database allows.
enum RiderAvailability {
  offline,
  available,
  onDelivery,
}

/// Reads the `rider_details.status` column.
///
/// Anything unrecognised is [RiderAvailability.offline] rather than
/// [RiderAvailability.available]: if the status is unreadable the safe answer
/// is "this rider is not taking work", never "accept more work".
RiderAvailability riderAvailabilityFromDatabaseValue(String? rawStatus) {
  switch (rawStatus?.trim().toLowerCase()) {
    case 'available':
      return RiderAvailability.available;
    case 'on_delivery':
      return RiderAvailability.onDelivery;
    default:
      return RiderAvailability.offline;
  }
}

/// The value to send to `rider_set_availability`.
String riderAvailabilityToDatabaseValue(RiderAvailability availability) {
  switch (availability) {
    case RiderAvailability.offline:
      return 'offline';
    case RiderAvailability.available:
      return 'available';
    case RiderAvailability.onDelivery:
      // Never sent directly: only the lifecycle functions may set this, so the
      // stored status can never disagree with the assignment the rider holds.
      return 'on_delivery';
  }
}
```

- [ ] **Step 4: Run and confirm green**

Run: `flutter test test/rider_availability_test.dart`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rider/models/rider_availability.dart test/rider_availability_test.dart
git commit -m "add rider availability model that reads unknown statuses as offline"
```

---

### Task 6: `RiderDelivery`

**Files:**
- Create: `lib/features/rider/models/rider_delivery.dart`
- Test: `test/rider_delivery_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `class RiderDelivery` with fields `assignmentId`, `orderId`, `billNumber`, `assignmentStatus`, `customerName`, `customerPhone`, `deliveryAddress`, `deliveryLatitude`, `deliveryLongitude`, `branchName`, `branchAddress`, `itemSummary`, `itemCount`, `assignedAt`, `pickedUpAt`, `deliveredAt`; `RiderDelivery.fromAssignmentRow(Map<String,dynamic>)`; `bool get isActive`, `bool get isOffer`, `bool get isHistory`, `bool get hasContactDetails`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/rider/models/rider_delivery.dart';

Map<String, dynamic> _row({
  String status = 'accepted',
  String? customerName = 'Usama Khan',
  String? customerPhone = '03001234567',
  String? deliveryAddress = 'Mandian, Abbottabad',
}) =>
    {
      'assignment_id': 'a1',
      'assignment_status': status,
      'order_id': 'o1',
      'bill_number': '#MP-84910',
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'delivery_address': deliveryAddress,
      'delivery_latitude': 34.1688,
      'delivery_longitude': 73.2215,
      'branch_name': 'Mr. Pizza – Abbottabad',
      'branch_address': 'Niazi Road, Abbottabad',
      'item_summary': '2x Zinger, 1x Coke',
      'item_count': 3,
      'assigned_at': '2026-09-28T10:00:00Z',
      'picked_up_at': null,
      'delivered_at': null,
    };

void main() {
  test('reads a full assignment row', () {
    final delivery = RiderDelivery.fromAssignmentRow(_row());
    expect(delivery.assignmentId, 'a1');
    expect(delivery.billNumber, '#MP-84910');
    expect(delivery.customerName, 'Usama Khan');
    expect(delivery.deliveryLatitude, 34.1688);
    expect(delivery.itemCount, 3);
  });

  test('an order placed before the snapshot has no usable contact details', () {
    final delivery = RiderDelivery.fromAssignmentRow(
      _row(customerName: null, customerPhone: null, deliveryAddress: null),
    );
    expect(delivery.hasContactDetails, isFalse);
    expect(delivery.customerName, '');
    expect(delivery.deliveryAddress, '');
    expect(delivery.deliveryLatitude, isNull);
  });

  test('classifies each lifecycle status', () {
    expect(
      RiderDelivery.fromAssignmentRow(_row(status: 'assigned')).isOffer, isTrue);
    expect(
      RiderDelivery.fromAssignmentRow(_row(status: 'accepted')).isActive,
      isTrue);
    expect(
      RiderDelivery.fromAssignmentRow(_row(status: 'picked_up')).isActive,
      isTrue);
    for (final finished in ['delivered', 'declined', 'failed']) {
      expect(
        RiderDelivery.fromAssignmentRow(_row(status: finished)).isHistory,
        isTrue,
        reason: '$finished should be history',
      );
    }
  });

  test('an unrecognised status is history, so it is never offered as work', () {
    final delivery = RiderDelivery.fromAssignmentRow(_row(status: 'wat'));
    expect(delivery.isHistory, isTrue);
    expect(delivery.isOffer, isFalse);
    expect(delivery.isActive, isFalse);
  });

  test('the three buckets never overlap', () {
    for (final status in [
      'assigned', 'accepted', 'picked_up', 'delivered', 'declined', 'failed'
    ]) {
      final d = RiderDelivery.fromAssignmentRow(_row(status: status));
      final buckets = [d.isOffer, d.isActive, d.isHistory].where((b) => b).length;
      expect(buckets, 1, reason: '$status landed in $buckets buckets');
    }
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/rider_delivery_test.dart`
Expected: FAIL — the file does not exist.

- [ ] **Step 3: Write the implementation**

```dart
/// One delivery assignment, joined to the order and branch it refers to.
///
/// The customer name, phone and address come from the snapshot columns on
/// `orders`, never from a customer profile lookup: a rider has no RLS access to
/// customer rows, and the address the customer had when they ordered is the one
/// the rider must deliver to.
class RiderDelivery {
  final String assignmentId;
  final String orderId;
  final String billNumber;
  final String assignmentStatus;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String branchName;
  final String branchAddress;
  final String itemSummary;
  final int itemCount;
  final DateTime? assignedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;

  const RiderDelivery({
    required this.assignmentId,
    required this.orderId,
    required this.billNumber,
    required this.assignmentStatus,
    required this.customerName,
    required this.customerPhone,
    required this.deliveryAddress,
    required this.deliveryLatitude,
    required this.deliveryLongitude,
    required this.branchName,
    required this.branchAddress,
    required this.itemSummary,
    required this.itemCount,
    required this.assignedAt,
    required this.pickedUpAt,
    required this.deliveredAt,
  });

  factory RiderDelivery.fromAssignmentRow(Map<String, dynamic> row) {
    return RiderDelivery(
      assignmentId: row['assignment_id'] as String,
      orderId: row['order_id'] as String,
      billNumber: (row['bill_number'] as String?) ?? '',
      assignmentStatus: (row['assignment_status'] as String?) ?? '',
      customerName: (row['customer_name'] as String?) ?? '',
      customerPhone: (row['customer_phone'] as String?) ?? '',
      deliveryAddress: (row['delivery_address'] as String?) ?? '',
      deliveryLatitude: (row['delivery_latitude'] as num?)?.toDouble(),
      deliveryLongitude: (row['delivery_longitude'] as num?)?.toDouble(),
      branchName: (row['branch_name'] as String?) ?? '',
      branchAddress: (row['branch_address'] as String?) ?? '',
      itemSummary: (row['item_summary'] as String?) ?? '',
      itemCount: (row['item_count'] as num?)?.toInt() ?? 0,
      assignedAt: _parseTimestamp(row['assigned_at']),
      pickedUpAt: _parseTimestamp(row['picked_up_at']),
      deliveredAt: _parseTimestamp(row['delivered_at']),
    );
  }

  static DateTime? _parseTimestamp(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  /// A job waiting for this rider to accept or decline it.
  bool get isOffer => assignmentStatus == 'assigned';

  /// A job this rider is currently doing.
  bool get isActive =>
      assignmentStatus == 'accepted' || assignmentStatus == 'picked_up';

  /// A job that has ended, one way or another.
  ///
  /// Anything unrecognised counts as history so an unknown status is never
  /// offered to a rider as work they might take.
  bool get isHistory =>
      !isOffer && !isActive;

  /// False for orders placed before the snapshot columns existed, and for any
  /// address the customer typed by hand without coordinates.
  bool get hasContactDetails =>
      customerPhone.isNotEmpty || deliveryAddress.isNotEmpty;

  /// A `geo:` URI for the delivery address, or null when there are no
  /// coordinates to point at.
  String? get mapsUrl {
    if (deliveryLatitude == null || deliveryLongitude == null) return null;
    return 'geo:$deliveryLatitude,$deliveryLongitude'
        '?q=${Uri.encodeComponent('$deliveryLatitude,$deliveryLongitude')}';
  }
}
```

- [ ] **Step 4: Run and confirm green**

Run: `flutter test test/rider_delivery_test.dart`
Expected: 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rider/models/rider_delivery.dart test/rider_delivery_test.dart
git commit -m "add rider delivery model reading the order contact snapshot and classifying each lifecycle status"
```

---

### Task 7: `delivery_actions.dart` — the pure rules

**Files:**
- Create: `lib/features/rider/logic/delivery_actions.dart`
- Test: `test/delivery_actions_test.dart`

**Interfaces:**
- Consumes: `RiderDelivery` from Task 6
- Produces: `enum RiderAction { accept, decline, markPickedUp, complete, fail }`, `class RiderActionButton { String label; RiderAction action; }`, `RiderActionButton? primaryActionFor(RiderDelivery)`, `List<RiderDelivery> pendingOffersFor(List<RiderDelivery>)`, `RiderDelivery? activeDeliveryFor(List<RiderDelivery>)`, `List<RiderDelivery> deliveredHistoryFor(List<RiderDelivery>)`, `double earningsFor(List<RiderDelivery>, double payoutPerDelivery)`, `int completedCountFor(List<RiderDelivery>)`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/rider/logic/delivery_actions.dart';
import 'package:mrpizza/features/rider/models/rider_delivery.dart';

RiderDelivery _delivery(String status, {String id = 'a'}) => RiderDelivery(
      assignmentId: id,
      orderId: 'o$id',
      billNumber: '#$id',
      assignmentStatus: status,
      customerName: 'Usama',
      customerPhone: '0300',
      deliveryAddress: 'Mandian',
      deliveryLatitude: 34.16,
      deliveryLongitude: 73.22,
      branchName: 'Abbottabad',
      branchAddress: 'Niazi Road',
      itemSummary: '2x Zinger',
      itemCount: 2,
      assignedAt: DateTime(2026, 9, 28),
      pickedUpAt: null,
      deliveredAt: null,
    );

void main() {
  group('the primary button follows the lifecycle', () {
    test('an accepted job offers pickup, not delivery', () {
      final button = primaryActionFor(_delivery('accepted'))!;
      expect(button.action, RiderAction.markPickedUp);
      expect(button.label, "I've Picked Up");
    });

    test('a picked up job offers completion', () {
      final button = primaryActionFor(_delivery('picked_up'))!;
      expect(button.action, RiderAction.complete);
      expect(button.label, 'Mark Delivered');
    });

    test('an offer has no single primary action, it is accepted or declined', () {
      expect(primaryActionFor(_delivery('assigned')), isNull);
    });

    test('a finished job has no primary action', () {
      for (final status in ['delivered', 'declined', 'failed', 'wat']) {
        expect(primaryActionFor(_delivery(status)), isNull,
            reason: '$status should offer no action');
      }
    });
  });

  group('the dashboard buckets never overlap', () {
    final all = [
      _delivery('assigned', id: '1'),
      _delivery('accepted', id: '2'),
      _delivery('picked_up', id: '3'),
      _delivery('delivered', id: '4'),
      _delivery('declined', id: '5'),
      _delivery('failed', id: '6'),
    ];

    test('every delivery lands in exactly one bucket', () {
      final seen = <String>{};
      for (final d in all) {
        final buckets = [
          pendingOffersFor(all),
          [if (activeDeliveryFor(all) != null) activeDeliveryFor(all)!],
          deliveredHistoryFor(all),
        ].expand((b) => b).map((d) => d.assignmentId).toList();
        expect(buckets.where((id) => id == d.assignmentId).length, 1,
            reason: '${d.assignmentId} appeared more than once');
      }
      expect(seen, isEmpty);
    });

    test('only assigned jobs are offered', () {
      expect(pendingOffersFor(all).map((d) => d.assignmentId), ['1']);
    });

    test('the active job is the accepted one, and pickup is not a second one', () {
      expect(activeDeliveryFor(all)?.assignmentId, '2');
      expect(activeDeliveryFor([_delivery('picked_up', id: '3')])?.assignmentId, '3');
    });

    test('history is everything that has ended', () {
      expect(
        deliveredHistoryFor(all).map((d) => d.assignmentId).toSet(),
        {'4', '5', '6'},
      );
    });

    test('no job means no active job and no crash', () {
      expect(activeDeliveryFor([]), isNull);
      expect(pendingOffersFor([]), isEmpty);
    });
  });

  group('earnings count delivered jobs only', () {
    test('uses the configured rate, not the delivery charge', () {
      final earnings = earningsFor(
        [_delivery('delivered', id: '1'), _delivery('delivered', id: '2')],
        250,
      );
      expect(earnings, 500);
    });

    test('ignores offers, active and failed jobs', () {
      final earnings = earningsFor([
        _delivery('assigned', id: '1'),
        _delivery('accepted', id: '2'),
        _delivery('picked_up', id: '3'),
        _delivery('failed', id: '4'),
        _delivery('declined', id: '5'),
      ], 250);
      expect(earnings, 0);
    });

    test('an unavailable rate does not invent money', () {
      expect(earningsFor([_delivery('delivered')], 0), 0);
      expect(completedCountFor([_delivery('delivered')]), 1);
    });
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/delivery_actions_test.dart`
Expected: FAIL — the file does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import '../models/rider_delivery.dart';

/// The six database transitions a rider can trigger.
enum RiderAction { accept, decline, markPickedUp, complete, fail }

/// The label and action for the dashboard's one big button.
class RiderActionButton {
  final String label;
  final RiderAction action;

  const RiderActionButton({required this.label, required this.action});
}

/// The single next step for the active job, or null when there is nothing to do
/// yet (an unaccepted offer) or nothing left to do (finished).
///
/// Kept free of Flutter and Supabase so the lifecycle can be tested directly.
RiderActionButton? primaryActionFor(RiderDelivery delivery) {
  switch (delivery.assignmentStatus) {
    case 'accepted':
      return const RiderActionButton(
          label: "I've Picked Up", action: RiderAction.markPickedUp);
    case 'picked_up':
      return const RiderActionButton(
          label: 'Mark Delivered', action: RiderAction.complete);
    default:
      return null;
  }
}

/// Jobs waiting for this rider to accept or decline.
List<RiderDelivery> pendingOffersFor(List<RiderDelivery> deliveries) =>
    deliveries.where((d) => d.isOffer).toList();

/// The job this rider is doing, if any. There is only ever one: the database
/// has no column for a second active assignment, and the dashboard shows a
/// single job card.
RiderDelivery? activeDeliveryFor(List<RiderDelivery> deliveries) {
  for (final delivery in deliveries) {
    if (delivery.isActive) return delivery;
  }
  return null;
}

/// Everything that has ended, newest first.
List<RiderDelivery> deliveredHistoryFor(List<RiderDelivery> deliveries) {
  final history = deliveries.where((d) => d.isHistory).toList()
    ..sort((a, b) {
      final aTime = a.deliveredAt ?? a.pickedUpAt ?? a.assignedAt;
      final bTime = b.deliveredAt ?? b.pickedUpAt ?? b.assignedAt;
      if (aTime == null || bTime == null) return 0;
      return bTime.compareTo(aTime);
    });
  return history;
}

/// Payout earned, using the store's configured rate per completed delivery.
///
/// A rate of zero means the rate could not be read; it must never be turned
/// into a nonzero figure by guessing.
double earningsFor(
  List<RiderDelivery> deliveries,
  double payoutPerDelivery,
) {
  if (payoutPerDelivery <= 0) return 0;
  return completedCountFor(deliveries) * payoutPerDelivery;
}

/// How many deliveries this rider has completed.
int completedCountFor(List<RiderDelivery> deliveries) =>
    deliveries.where((d) => d.assignmentStatus == 'delivered').length;
```

- [ ] **Step 4: Run and confirm green**

Run: `flutter test test/delivery_actions_test.dart`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rider/logic/delivery_actions.dart test/delivery_actions_test.dart
git commit -m "add pure rider delivery rules: one primary action per status and non overlapping buckets"
```

---

### Task 8: `RiderRepository` — transitions only, no direct writes

**Files:**
- Create: `lib/features/rider/data/rider_repository.dart`
- Modify: `pubspec.yaml` — add `http: ^1.2.0` to `dev_dependencies`
- Test: `test/rider_repository_test.dart`

**Interfaces:**
- Consumes: the six function names from Task 2, `RiderDelivery` from Task 6
- Produces: `class RiderRepository` with `Future<RiderDetails?> fetchRiderDetails()`, `Future<List<RiderDelivery>> fetchDeliveries()`, `Future<double> fetchPayoutRate()`, `Future<void> claimOffer(String)`, `Future<void> declineOffer(String)`, `Future<void> markPickedUp(String)`, `Future<void> completeDelivery(String)`, `Future<void> failDelivery(String, String)`, `Future<void> setAvailability(String)`, and `RiderRepositoryException`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mrpizza/features/rider/data/rider_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _requests = <http.Request>[];

SupabaseClient _clientReturning(String body) {
  return SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: MockClient((request) async {
      _requests.add(request);
      return http.Response(body, 200,
          headers: {'content-type': 'application/json'});
    }),
  );
}

SupabaseClient _clientFailing() {
  return SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: MockClient((request) async {
      _requests.add(request);
      return http.Response(
        jsonEncode({'message': 'This delivery is no longer available'}),
        400,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

String _functionCalledBy(http.Request request) =>
    request.url.path.split('/rest/v1/rpc/').last;

void main() {
  setUp(_requests.clear);

  test('claiming an offer calls rider_claim_offer for that assignment', () async {
    final repository = RiderRepository(client: _clientReturning('{}'));
    await repository.claimOffer('assignment-1');

    expect(_requests, hasLength(1));
    expect(_functionCalledBy(_requests.single), 'rider_claim_offer');
    expect(_requests.single.method, 'POST');
    expect(jsonDecode(_requests.single.body),
        {'p_assignment_id': 'assignment-1'});
  });

  test('every transition maps to its own database function', () async {
    final repository = RiderRepository(client: _clientReturning('{}'));
    await repository.declineOffer('a');
    await repository.markPickedUp('a');
    await repository.completeDelivery('a');
    await repository.failDelivery('a', 'customer not answering');

    expect(_requests.map(_functionCalledBy).toList(), [
      'rider_decline_offer',
      'rider_mark_picked_up',
      'rider_complete_delivery',
      'rider_fail_delivery',
    ]);
    expect(jsonDecode(_requests.last.body), {
      'p_assignment_id': 'a',
      'p_reason': 'customer not answering',
    });
  });

  test('setting availability calls rider_set_availability', () async {
    final repository = RiderRepository(client: _clientReturning('{}'));
    await repository.setAvailability('available');

    expect(_functionCalledBy(_requests.single), 'rider_set_availability');
    expect(jsonDecode(_requests.single.body), {'p_status': 'available'});
  });

  test('a rejected transition surfaces the database message', () async {
    final repository = RiderRepository(client: _clientFailing());

    await expectLater(
      repository.claimOffer('a'),
      throwsA(
        isA<RiderRepositoryException>()
            .having((e) => e.message, 'message',
                'This delivery is no longer available'),
      ),
    );
  });

  test('deliveries are read from the rider own assignments', () async {
    final repository = RiderRepository(
      client: _clientReturning(jsonEncode([
        {
          'assignment_id': 'a1',
          'assignment_status': 'assigned',
          'order_id': 'o1',
          'bill_number': '#MP-1',
          'customer_name': 'Usama',
          'customer_phone': '0300',
          'delivery_address': 'Mandian',
          'delivery_latitude': 34.16,
          'delivery_longitude': 73.22,
          'branch_name': 'Abbottabad',
          'branch_address': 'Niazi Road',
          'item_summary': '1x Zinger',
          'item_count': 1,
          'assigned_at': '2026-09-28T10:00:00Z',
          'picked_up_at': null,
          'delivered_at': null,
        }
      ])),
    );

    final deliveries = await repository.fetchDeliveries();

    expect(deliveries, hasLength(1));
    expect(deliveries.single.assignmentId, 'a1');
    expect(_functionCalledBy(_requests.single), 'rider_deliveries');
  });

  test('the repository never writes the rider tables directly', () {
    final source = File(
      'lib/features/rider/data/rider_repository.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('.update(')));
    expect(source, isNot(contains('.insert(')));
    expect(source, isNot(contains('.delete(')));
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/rider_repository_test.dart`
Expected: FAIL — the file does not exist.

- [ ] **Step 3: Add `http` to dev_dependencies**

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  http: ^1.2.0
```

Run: `flutter pub get`

- [ ] **Step 4: Write the implementation**

```dart
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postgrest/postgrest.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/supabase_client.dart';
import '../models/rider_availability.dart';
import '../models/rider_delivery.dart';

/// A transition the database refused, carrying the reason it gave.
class RiderRepositoryException implements Exception {
  final String message;

  const RiderRepositoryException(this.message);

  @override
  String toString() => message;
}

/// Everything the rider screen needs from the database.
///
/// This class issues no table writes. Every lifecycle change goes through a
/// database function, so the assignment, the order status and the history row
/// can never disagree, and a rejected transition arrives here as a
/// [RiderRepositoryException] carrying the database's own wording.
class RiderRepository {
  /// Resolved lazily on purpose. `supabase` throws when the client has not been
  /// initialised, so a test that subclasses this repository and overrides every
  /// method must not trigger it just by being constructed.
  final SupabaseClient? _injectedClient;

  RiderRepository({SupabaseClient? client}) : _injectedClient = client;

  /// The client to talk to, injected in tests and the global one in the app.
  SupabaseClient get client => _injectedClient ?? supabase;

  /// The rider's own record, or null when the panel has not created it yet.
  Future<RiderDetails?> fetchRiderDetails() async {
    final rows = await _client
        .from('rider_details')
        .select('branch_id, status, branch:branches(name, address)')
        .maybeSingle();
    if (rows == null) return null;
    return RiderDetails.fromMap(rows);
  }

  /// The rider's assignments joined to the order contact snapshot and branch.
  Future<List<RiderDelivery>> fetchDeliveries() async {
    final rows = await _client.rpc('rider_deliveries');
    return (rows as List)
        .map((row) => RiderDelivery.fromAssignmentRow(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
  }

  /// The store's configured payout per completed delivery, or 0 when it cannot
  /// be read. Zero is passed through to the earnings rule, which then reports
  /// 0 rather than inventing a figure.
  Future<double> fetchPayoutRate() async {
    final row = await _client
        .from('store_settings')
        .select('rider_payout_per_delivery')
        .maybeSingle();
    if (row == null) return 0;
    final value = row['rider_payout_per_delivery'];
    if (value is num) return value.toDouble();
    return 0;
  }

  Future<void> claimOffer(String assignmentId) =>
      _callTransition('rider_claim_offer', {'p_assignment_id': assignmentId});

  Future<void> declineOffer(String assignmentId) => _callTransition(
      'rider_decline_offer', {'p_assignment_id': assignmentId});

  Future<void> markPickedUp(String assignmentId) => _callTransition(
      'rider_mark_picked_up', {'p_assignment_id': assignmentId});

  Future<void> completeDelivery(String assignmentId) => _callTransition(
      'rider_complete_delivery', {'p_assignment_id': assignmentId});

  Future<void> failDelivery(String assignmentId, String reason) =>
      _callTransition('rider_fail_delivery', {
        'p_assignment_id': assignmentId,
        'p_reason': reason,
      });

  Future<void> setAvailability(String status) =>
      _callTransition('rider_set_availability', {'p_status': status});

  Future<void> _callTransition(String function, Map<String, dynamic> params) async {
    try {
      await _client.rpc(function, params: params);
    } on PostgrestException catch (error) {
      throw RiderRepositoryException(
        error.message.isEmpty
            ? 'That did not go through. Pull to refresh and try again.'
            : error.message,
      );
    }
  }
}

/// The rider's own record, used to tell "not set up yet" from "set up".
class RiderDetails {
  final String? branchId;
  final RiderAvailability availability;
  final String branchName;
  final String branchAddress;

  const RiderDetails({
    required this.branchId,
    required this.availability,
    required this.branchName,
    required this.branchAddress,
  });

  factory RiderDetails.fromMap(Map<String, dynamic> row) {
    final branch = row['branch'];
    final branchMap = branch is Map
        ? Map<String, dynamic>.from(branch)
        : <String, dynamic>{};
    return RiderDetails(
      branchId: row['branch_id'] as String?,
      availability: riderAvailabilityFromDatabaseValue(row['status'] as String?),
      branchName: (branchMap['name'] as String?) ?? '',
      branchAddress: (branchMap['address'] as String?) ?? '',
    );
  }
}

final riderRepositoryProvider = Provider<RiderRepository>(
  (ref) => RiderRepository(),
);
```

- [ ] **Step 5: Add the read function to migration 2's file, then commit**

`rider_deliveries` does not exist yet — append it to `supabase/migrations/20260928091000_rider_transition_functions.sql`:

```sql
-- The rider's own assignments, joined to the order contact snapshot and the
-- branch. Read-only: this is the only SELECT a rider makes on their work.
create or replace function public.rider_deliveries()
returns table (
  assignment_id      uuid,
  assignment_status  text,
  order_id           uuid,
  bill_number        text,
  customer_name      text,
  customer_phone     text,
  delivery_address   text,
  delivery_latitude  numeric,
  delivery_longitude numeric,
  branch_name        text,
  branch_address     text,
  item_summary       text,
  item_count         bigint,
  assigned_at        timestamptz,
  picked_up_at       timestamptz,
  delivered_at       timestamptz
)
language sql
stable
security definer
set search_path to 'public'
as $$
  select
    ra.id,
    ra.status,
    o.id,
    o.bill_serial_number,
    o.customer_name,
    o.customer_phone,
    o.delivery_address,
    o.delivery_latitude,
    o.delivery_longitude,
    b.name,
    b.address,
    coalesce((
      select string_agg(oi.quantity || 'x ' || mi.name, ', '
                           order by mi.name)
        from public.order_items oi
        join public.menu_items mi on mi.id = oi.menu_item_id
       where oi.order_id = o.id
    ), ''),
    (select count(*) from public.order_items oi where oi.order_id = o.id),
    ra.assigned_at,
    ra.picked_up_at,
    ra.delivered_at
  from public.rider_assignments ra
  join public.orders o   on o.id = ra.order_id
  join public.branches b on b.id = o.branch_id
  where ra.rider_id = (select auth.uid())
  order by ra.assigned_at desc;
$$;

revoke execute on function public.rider_deliveries() from public;
grant execute on function public.rider_deliveries() to authenticated;
```

Then commit:

```bash
git add lib/features/rider/data/rider_repository.dart test/rider_repository_test.dart pubspec.yaml pubspec.lock supabase/migrations/20260928091000_rider_transition_functions.sql
git commit -m "add rider repository that goes through database functions only and never writes the rider tables"
```

---

### Task 9: Rider providers

**Files:**
- Create: `lib/features/rider/providers/rider_providers.dart`
- Test: `test/rider_providers_test.dart`

**Interfaces:**
- Consumes: `RiderRepository` from Task 8, `RiderAvailability` from Task 5, `RiderDelivery` from Task 6, `delivery_actions.dart` from Task 7
- Produces: `riderDetailsProvider`, `riderDeliveriesProvider`, `payoutRateProvider`, `riderAvailabilityProvider`, `riderEarningsProvider`, `riderAvailabilityController`, `riderTransitionController`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/rider/data/rider_repository.dart';
import 'package:mrpizza/features/rider/models/rider_availability.dart';
import 'package:mrpizza/features/rider/models/rider_delivery.dart';
import 'package:mrpizza/features/rider/providers/rider_providers.dart';

class _FakeRiderRepository extends RiderRepository {
  _FakeRiderRepository({
    this.details,
    this.deliveries = const [],
    this.payoutRate = 250,
  });

  final RiderDetails? details;
  final List<RiderDelivery> deliveries;
  final double payoutRate;
  final List<String> called = [];

  @override
  Future<RiderDetails?> fetchRiderDetails() async => details;

  @override
  Future<List<RiderDelivery>> fetchDeliveries() async => deliveries;

  @override
  Future<double> fetchPayoutRate() async => payoutRate;

  @override
  Future<void> claimOffer(String id) async => called.add('claim');
  @override
  Future<void> declineOffer(String id) async => called.add('decline');
  @override
  Future<void> markPickedUp(String id) async => called.add('pickup');
  @override
  Future<void> completeDelivery(String id) async => called.add('complete');
  @override
  Future<void> failDelivery(String id, String reason) async =>
      called.add('fail');
  @override
  Future<void> setAvailability(String status) async =>
      called.add('availability:$status');
}

RiderDelivery _delivery(String status) => RiderDelivery(
      assignmentId: 'a',
      orderId: 'o',
      billNumber: '#1',
      assignmentStatus: status,
      customerName: 'Usama',
      customerPhone: '0300',
      deliveryAddress: 'Mandian',
      deliveryLatitude: 34.16,
      deliveryLongitude: 73.22,
      branchName: 'Abbottabad',
      branchAddress: 'Niazi Road',
      itemSummary: '1x Zinger',
      itemCount: 1,
      assignedAt: DateTime(2026, 9, 28),
      pickedUpAt: null,
      deliveredAt: null,
    );

void main() {
  test('a rider with no record is reported, not treated as set up', () async {
    final container = ProviderContainer(
      overrides: [riderRepositoryProvider.overrideWithValue(
          _FakeRiderRepository(details: null))],
    );
    addTearDown(container.dispose);

    expect(await container.read(riderDetailsProvider.future), isNull);
  });

  test('availability is derived from the rider record', () async {
    final container = ProviderContainer(
      overrides: [
        riderRepositoryProvider.overrideWithValue(
          _FakeRiderRepository(
            details: const RiderDetails(
              branchId: 'b1',
              availability: RiderAvailability.available,
              branchName: 'Abbottabad',
              branchAddress: 'Niazi Road',
            ),
          ),
        )
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(riderAvailabilityProvider.future),
        RiderAvailability.available);
  });

  test('earnings use the configured rate', () async {
    final container = ProviderContainer(
      overrides: [
        riderRepositoryProvider.overrideWithValue(_FakeRiderRepository(
          details: const RiderDetails(
            branchId: 'b1',
            availability: RiderAvailability.available,
            branchName: 'A',
            branchAddress: 'B',
          ),
          deliveries: [_delivery('delivered'), _delivery('accepted')],
          payoutRate: 250,
        ))
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(riderEarningsProvider.future), 250);
  });

  test('an unreadable rate never turns into invented money', () async {
    final container = ProviderContainer(
      overrides: [
        riderRepositoryProvider.overrideWithValue(_FakeRiderRepository(
          details: const RiderDetails(
            branchId: 'b1',
            availability: RiderAvailability.available,
            branchName: 'A',
            branchAddress: 'B',
          ),
          deliveries: [_delivery('delivered')],
          payoutRate: 0,
        ))
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(riderEarningsProvider.future), 0);
  });

  test('a transition invalidates the deliveries so the screen re-reads',
      () async {
    final fake = _FakeRiderRepository(
      details: const RiderDetails(
        branchId: 'b1',
        availability: RiderAvailability.available,
        branchName: 'A',
        branchAddress: 'B',
      ),
    );
    final container = ProviderContainer(
      overrides: [riderRepositoryProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container.read(riderDeliveriesProvider.future);
    await container.read(riderTransitionController).claimOffer('a');

    expect(fake.called, ['claim']);
    expect(container.read(riderDeliveriesProvider), isA<AsyncValue<List<RiderDelivery>>>());
  });

  test('going offline sends the database value, not the enum name', () async {
    final fake = _FakeRiderRepository(
      details: const RiderDetails(
        branchId: 'b1',
        availability: RiderAvailability.available,
        branchName: 'A',
        branchAddress: 'B',
      ),
    );
    final container = ProviderContainer(
      overrides: [riderRepositoryProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    await container.read(riderAvailabilityController).goOffline();

    expect(fake.called, ['availability:offline']);
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/rider_providers_test.dart`
Expected: FAIL — the file does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/rider_repository.dart';
import '../logic/delivery_actions.dart';
import '../models/rider_availability.dart';
import '../models/rider_delivery.dart';

/// The rider's own record. Null means the panel has not created it yet, which
/// the dashboard shows as a setup message rather than an empty screen.
final riderDetailsProvider = FutureProvider<RiderDetails?>((ref) async {
  return ref.watch(riderRepositoryProvider).fetchRiderDetails();
});

/// The rider's assignments, newest first.
final riderDeliveriesProvider = FutureProvider<List<RiderDelivery>>((ref) async {
  return ref.watch(riderRepositoryProvider).fetchDeliveries();
});

/// The store's payout per completed delivery. 0 means unreadable.
final payoutRateProvider = FutureProvider<double>((ref) async {
  return ref.watch(riderRepositoryProvider).fetchPayoutRate();
});

final riderAvailabilityProvider = FutureProvider<RiderAvailability>((ref) async {
  final details = await ref.watch(riderDetailsProvider.future);
  return details?.availability ?? RiderAvailability.offline;
});

/// Payout earned so far. Zero when the rate could not be read, never a guess.
final riderEarningsProvider = FutureProvider<double>((ref) async {
  final deliveries = await ref.watch(riderDeliveriesProvider.future);
  final rate = await ref.watch(payoutRateProvider.future);
  return earningsFor(deliveries, rate);
});

/// Going online and offline. The database refuses to mark a rider available
/// while they hold a job, and surfaces that refusal to the caller.
class RiderAvailabilityController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> goOnline() => _set('available');

  Future<void> goOffline() => _set('offline');

  Future<void> _set(String status) async {
    state = const AsyncLoading();
    try {
      await ref.read(riderRepositoryProvider).setAvailability(status);
      ref.invalidate(riderDetailsProvider);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

final riderAvailabilityController =
    NotifierProvider<RiderAvailabilityController, AsyncValue<void>>(
        RiderAvailabilityController.new);

/// The six lifecycle transitions, each of which invalidates the deliveries so
/// the dashboard re-reads the truth from the database instead of patching local
/// state optimistically.
class RiderTransitionController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> claimOffer(String assignmentId) =>
      _run(() => ref.read(riderRepositoryProvider).claimOffer(assignmentId));

  Future<void> declineOffer(String assignmentId) => _run(
      () => ref.read(riderRepositoryProvider).declineOffer(assignmentId));

  Future<void> markPickedUp(String assignmentId) => _run(
      () => ref.read(riderRepositoryProvider).markPickedUp(assignmentId));

  Future<void> completeDelivery(String assignmentId) => _run(
      () => ref.read(riderRepositoryProvider).completeDelivery(assignmentId));

  Future<void> failDelivery(String assignmentId, String reason) => _run(
      () => ref.read(riderRepositoryProvider).failDelivery(assignmentId, reason));

  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      ref.invalidate(riderDeliveriesProvider);
      ref.invalidate(riderDetailsProvider);
      state = const AsyncData(null);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}

final riderTransitionController =
    NotifierProvider<RiderTransitionController, AsyncValue<void>>(
        RiderTransitionController.new);
```

- [ ] **Step 4: Run and confirm green**

Run: `flutter test test/rider_providers_test.dart`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rider/providers/rider_providers.dart test/rider_providers_test.dart
git commit -m "add rider providers that derive availability and earnings from the database"
```

---

### Task 10: Checkout writes the delivery contact snapshot

**Files:**
- Modify: `lib/features/orders/models/order.dart:66-94`
- Modify: `lib/features/payment/screens/checkout_screen.dart` — find the `OrdersRepository.placeOrder` call
- Test: `test/order_snapshot_test.dart`

**Interfaces:**
- Consumes: `UserAddress` from `lib/features/profile/models/profile.dart`, `profileFutureProvider`
- Produces: `Order` gains `customerName`, `customerPhone`, `deliveryAddress`, `deliveryLatitude`, `deliveryLongitude`; `toInsertMap()` includes the five snapshot columns

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/orders/models/order.dart';

void main() {
  test('toInsertMap carries the delivery contact snapshot', () {
    final order = Order(
      customerId: 'c1',
      branchId: 'b1',
      addressId: 'a1',
      orderType: OrderType.delivery,
      totals: const OrderTotals(
        subtotal: 1000,
        tax: 100,
        deliveryFee: 150,
        discount: 0,
        total: 1250,
      ),
      items: const [],
      customerName: 'Usama Khan',
      customerPhone: '03001234567',
      deliveryAddress: 'Mandian, Abbottabad',
      deliveryLatitude: 34.1688,
      deliveryLongitude: 73.2215,
    );

    final map = order.toInsertMap();

    expect(map['customer_name'], 'Usama Khan');
    expect(map['customer_phone'], '03001234567');
    expect(map['delivery_address'], 'Mandian, Abbottabad');
    expect(map['delivery_latitude'], 34.1688);
    expect(map['delivery_longitude'], 73.2215);
  });

  test('a pickup order still records the snapshot, as empty values', () {
    final order = Order(
      customerId: 'c1',
      branchId: 'b1',
      addressId: null,
      orderType: OrderType.pickup,
      totals: const OrderTotals(
        subtotal: 1000,
        tax: 100,
        deliveryFee: 0,
        discount: 0,
        total: 1100,
      ),
      items: const [],
    );

    final map = order.toInsertMap();

    expect(map['customer_name'], '');
    expect(map['delivery_address'], '');
    expect(map['delivery_latitude'], isNull);
  });

  test('bill_serial_number is still not generated in the app', () {
    final order = Order(
      customerId: 'c1',
      branchId: 'b1',
      addressId: null,
      orderType: OrderType.pickup,
      totals: const OrderTotals(
        subtotal: 1, tax: 0, deliveryFee: 0, discount: 0, total: 1),
      items: const [],
    );

    expect(order.toInsertMap().containsKey('bill_serial_number'), isFalse);
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/order_snapshot_test.dart`
Expected: FAIL — `Order` has no `customerName` parameter.

- [ ] **Step 3: Add the fields to `Order`**

In `lib/features/orders/models/order.dart`, add to the field list and constructor:

```dart
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
```

```dart
  const Order({
    required this.customerId,
    required this.branchId,
    required this.addressId,
    required this.orderType,
    required this.totals,
    required this.items,
    this.status = 'confirmed',
    this.customerName = '',
    this.customerPhone = '',
    this.deliveryAddress = '',
    this.deliveryLatitude,
    this.deliveryLongitude,
  });
```

And extend `toInsertMap()`:

```dart
  Map<String, dynamic> toInsertMap() {
    return {
      'customer_id': customerId,
      'branch_id': branchId,
      'address_id': addressId,
      'order_type': orderType.dbValue,
      'status': status,
      'subtotal': totals.subtotal,
      'tax': totals.tax,
      'delivery_charges': totals.deliveryFee,
      'total': totals.total,
      // Snapshot: a rider cannot read the customer's profiles or addresses
      // rows, so the details they need to make the delivery are copied here at
      // the moment the order is placed.
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'delivery_address': deliveryAddress,
      'delivery_latitude': deliveryLatitude,
      'delivery_longitude': deliveryLongitude,
    };
  }
```

- [ ] **Step 4: Populate them at the checkout call site**

Find the `OrdersRepository.placeOrder(...)` call in `checkout_screen.dart`. At that point a `UserAddress?` for the chosen delivery address and a profile are already in scope. Populate:

```dart
final selectedAddress = /* the UserAddress the customer chose, or null for pickup */;
final profile = ref.read(profileFutureProvider).value;

await ref.read(ordersRepositoryProvider).placeOrder(
      Order(
        customerId: ref.read(currentUserIdProvider)!,
        branchId: chosenBranch.id,
        addressId: selectedAddress?.id,
        orderType: delivery ? OrderType.delivery : OrderType.pickup,
        totals: totals,
        items: cartItems,
        customerName: profile?.fullName.trim() ?? '',
        customerPhone: profile?.phone.trim() ?? '',
        deliveryAddress: selectedAddress?.addressLine.trim() ?? '',
        deliveryLatitude: selectedAddress?.latitude,
        deliveryLongitude: selectedAddress?.longitude,
      ),
    );
```

If the local variable names differ, keep the same field mapping — the test in Step 1 pins the behaviour, not the call site.

- [ ] **Step 5: Run the whole suite**

Run: `flutter test`
Expected: all tests pass, including the pre-existing 179.

- [ ] **Step 6: Commit**

```bash
git add lib/features/orders/models/order.dart lib/features/payment/screens/checkout_screen.dart test/order_snapshot_test.dart
git commit -m "snapshot the delivery contact onto the order at checkout so riders never need customer row access"
```

---

# Phase 3 — UI

### Task 11: Rider routes and guard

**Files:**
- Modify: `lib/core/routing/route_guard.dart:12-20`
- Modify: `lib/core/routing/router.dart` — add two routes
- Test: `test/rider_routes_test.dart`

**Interfaces:**
- Consumes: `resolveAuthorizedLocation` from the earlier session
- Produces: `riderHistoryLocation = '/rider/history'`, `riderEarningsLocation = '/rider/earnings'`, both in `riderOnlyLocations`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/role_provider.dart';
import 'package:mrpizza/core/routing/route_guard.dart';

void main() {
  test('a customer is kept out of the rider history and earnings screens', () {
    for (final location in [
      riderHistoryLocation,
      riderEarningsLocation,
      riderLandingLocation,
    ]) {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.customer,
          requestedLocation: location,
        ),
        customerLandingLocation,
        reason: '$location should be closed to customers',
      );
    }
  });

  test('a rider may open all three rider screens', () {
    for (final location in [
      riderHistoryLocation,
      riderEarningsLocation,
      riderLandingLocation,
    ]) {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: true,
          role: UserRole.rider,
          requestedLocation: location,
        ),
        isNull,
        reason: '$location should be open to riders',
      );
    }
  });

  test('a signed out visitor is sent to login from all three', () {
    for (final location in [
      riderHistoryLocation,
      riderEarningsLocation,
      riderLandingLocation,
    ]) {
      expect(
        resolveAuthorizedLocation(
          isAuthenticated: false,
          role: UserRole.customer,
          requestedLocation: location,
        ),
        loginLocation,
      );
    }
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/rider_routes_test.dart`
Expected: FAIL — the two locations do not exist.

- [ ] **Step 3: Add the locations to the guard**

In `lib/core/routing/route_guard.dart`:

```dart
const riderHistoryLocation = '/rider/history';

const riderEarningsLocation = '/rider/earnings';

const riderOnlyLocations = <String>{
  riderLandingLocation,
  riderHistoryLocation,
  riderEarningsLocation,
};
```

- [ ] **Step 4: Add the routes to the router**

In `lib/core/routing/router.dart`, add the imports and two `GoRoute`s:

```dart
import '../../features/rider/screens/rider_earnings_screen.dart';
import '../../features/rider/screens/rider_history_screen.dart';
```

```dart
      GoRoute(
        path: riderHistoryLocation,
        builder: (context, state) => const RiderHistoryScreen(),
      ),
      GoRoute(
        path: riderEarningsLocation,
        builder: (context, state) => const RiderEarningsScreen(),
      ),
```

Create the two screens now as placeholders that Task 13 fills in — they must exist for this to compile:

```dart
// lib/features/rider/screens/rider_history_screen.dart
import 'package:flutter/material.dart';

class RiderHistoryScreen extends StatelessWidget {
  const RiderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Rider History')));
}
```

```dart
// lib/features/rider/screens/rider_earnings_screen.dart
import 'package:flutter/material.dart';

class RiderEarningsScreen extends StatelessWidget {
  const RiderEarningsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Rider Earnings')));
}
```

- [ ] **Step 5: Run and confirm green**

Run: `flutter test test/rider_routes_test.dart && flutter analyze`
Expected: 3 tests pass, analyze clean.

- [ ] **Step 6: Commit**

```bash
git add lib/core/routing/route_guard.dart lib/core/routing/router.dart lib/features/rider/screens/rider_history_screen.dart lib/features/rider/screens/rider_earnings_screen.dart test/rider_routes_test.dart
git commit -m "add rider history and earnings routes behind the rider guard"
```

---

### Task 12: The rider dashboard

**Files:**
- Rewrite: `lib/features/rider/screens/rider_screen.dart` (currently 956 lines of demo data)
- Delete: `lib/features/orders/providers/order_flow_provider.dart` (demo only — verify nothing else imports it first)
- Test: `test/rider_dashboard_test.dart`

**Interfaces:**
- Consumes: everything from Task 9, `primaryActionFor` from Task 7, `RiderDelivery` from Task 6
- Produces: `RiderScreen` rendering one of five states

- [ ] **Step 1: Confirm nothing else imports the demo provider**

```bash
Select-String -Path lib/**/*.dart -Pattern "orderFlowProvider|DemoOrder"
```

Expected: only `rider_screen.dart` and `order_flow_provider.dart` itself. If anything else references it, stop and report before deleting.

- [ ] **Step 2: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/app_theme.dart';
import 'package:mrpizza/features/rider/data/rider_repository.dart';
import 'package:mrpizza/features/rider/models/rider_availability.dart';
import 'package:mrpizza/features/rider/models/rider_delivery.dart';
import 'package:mrpizza/features/rider/providers/rider_providers.dart';
import 'package:mrpizza/features/rider/screens/rider_screen.dart';

class _FakeRiderRepository extends RiderRepository {
  _FakeRiderRepository({this.details, this.deliveries = const []});

  final RiderDetails? details;
  final List<RiderDelivery> deliveries;
  String? lastAvailability;

  @override
  Future<RiderDetails?> fetchRiderDetails() async => details;

  @override
  Future<List<RiderDelivery>> fetchDeliveries() async => deliveries;

  @override
  Future<double> fetchPayoutRate() async => 250;

  @override
  Future<void> setAvailability(String status) async =>
      lastAvailability = status;
}

const _branch = 'b1';

RiderDetails _details(RiderAvailability availability) => RiderDetails(
      branchId: _branch,
      availability: availability,
      branchName: 'Abbottabad',
      branchAddress: 'Niazi Road',
    );

RiderDelivery _delivery({
  String status = 'accepted',
  String? customerName = 'Usama Khan',
  String? customerPhone = '03001234567',
  String? deliveryAddress = 'Mandian, Abbottabad',
}) =>
    RiderDelivery(
      assignmentId: 'a1',
      orderId: 'o1',
      billNumber: '#MP-84910',
      assignmentStatus: status,
      customerName: customerName ?? '',
      customerPhone: customerPhone ?? '',
      deliveryAddress: deliveryAddress ?? '',
      deliveryLatitude: 34.1688,
      deliveryLongitude: 73.2215,
      branchName: 'Abbottabad',
      branchAddress: 'Niazi Road',
      itemSummary: '2x Zinger, 1x Coke',
      itemCount: 3,
      assignedAt: DateTime(2026, 9, 28, 10),
      pickedUpAt: null,
      deliveredAt: null,
    );

Widget _app(_FakeRiderRepository repository) => ProviderScope(
      overrides: [riderRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const RiderScreen(),
      ),
    );

void main() {
  testWidgets('a rider with no record is told to contact the branch, not shown a blank screen',
      (tester) async {
    await tester.pumpWidget(_app(_FakeRiderRepository(details: null)));
    await tester.pumpAndSettle();

    expect(find.textContaining('not set up'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an available rider with no work sees the empty state',
      (tester) async {
    await tester.pumpWidget(_app(_FakeRiderRepository(
      details: _details(RiderAvailability.available),
    )));
    await tester.pumpAndSettle();

    expect(find.text('No deliveries waiting'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pending offer shows accept and decline', (tester) async {
    await tester.pumpWidget(_app(_FakeRiderRepository(
      details: _details(RiderAvailability.available),
      deliveries: [_delivery(status: 'assigned')],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an accepted job shows the customer, address and pickup button',
      (tester) async {
    await tester.pumpWidget(_app(_FakeRiderRepository(
      details: _details(RiderAvailability.onDelivery),
      deliveries: [_delivery(status: 'accepted')],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Usama Khan'), findsOneWidget);
    expect(find.text('Mandian, Abbottabad'), findsOneWidget);
    expect(find.text("I've Picked Up"), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Open in Maps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a picked up job offers completion, not pickup', (tester) async {
    await tester.pumpWidget(_app(_FakeRiderRepository(
      details: _details(RiderAvailability.onDelivery),
      deliveries: [_delivery(status: 'picked_up')],
    )));
    await tester.pumpAndSettle();

    expect(find.text('Mark Delivered'), findsOneWidget);
    expect(find.text("I've Picked Up"), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old order with no snapshot says so instead of showing blanks',
      (tester) async {
    await tester.pumpWidget(_app(_FakeRiderRepository(
      details: _details(RiderAvailability.onDelivery),
      deliveries: [
        _delivery(
          status: 'accepted',
          customerName: null,
          customerPhone: null,
          deliveryAddress: null,
        )
      ],
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('Contact details unavailable'), findsOneWidget);
    expect(find.text('Call'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('today shows the completed count and the configured payout',
      (tester) async {
    await tester.pumpWidget(_app(_FakeRiderRepository(
      details: _details(RiderAvailability.available),
      deliveries: [_delivery(status: 'delivered')],
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('1'), findsWidgets);
    expect(find.textContaining('250'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 3: Run and watch them fail**

Run: `flutter test test/rider_dashboard_test.dart`
Expected: FAIL — the current screen renders the old demo.

- [ ] **Step 4: Write the dashboard**

Rewrite `lib/features/rider/screens/rider_screen.dart`. Structure, in order top to bottom: availability toggle, today's strip, active job card, pending offers, recent deliveries preview. Use the existing `MrCard`, `MrSectionTitle`, `MrIconWell` and `AppColors` from `core/theme/widgets.dart` and `core/theme/app_colors.dart` so the screen matches the customer app.

Key pieces:

```dart
class RiderScreen extends ConsumerWidget {
  const RiderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(riderDetailsProvider);

    return detailsAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _RiderSetupMessage(
        message: 'Could not load your rider account.',
        detail: '$error',
        onRetry: () => ref.invalidate(riderDetailsProvider),
      ),
      data: (details) {
        if (details == null) {
          return _RiderSetupMessage(
            message: 'Your rider account is not set up yet.',
            detail: 'Ask the branch to add you, then pull down to refresh.',
            onRetry: () => ref.invalidate(riderDetailsProvider),
          );
        }
        return _RiderDashboard(details: details);
      },
    );
  }
}
```

The availability toggle must send the database value and surface a refusal in the rider's own words, because "Finish your current delivery first" is the message the database raises when a rider tries to go available mid-job:

```dart
Future<void> _toggleAvailability(BuildContext context, WidgetRef ref) async {
  final current = ref.read(riderAvailabilityProvider).valueOrNull ??
      RiderAvailability.offline;
  final controller = ref.read(riderAvailabilityController.notifier);
  try {
    if (current == RiderAvailability.available) {
      await controller.goOffline();
    } else {
      await controller.goOnline();
    }
  } on RiderRepositoryException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}
```

Call the public `goOnline()` / `goOffline()` methods from Task 9. Never call the private `_set`.

The job card must show the Call button only when there is a number, and the maps button only when there are coordinates — that is what makes the "old order with no snapshot" test pass:

```dart
if (delivery.hasContactDetails) ...[
  MrIconWell(icon: Icons.phone_rounded),
  const Text('Call'),
],
if (delivery.mapsUrl != null) ...[
  MrIconWell(icon: Icons.map_rounded),
  const Text('Open in Maps'),
],
```

and, when `!delivery.hasContactDetails`:

```dart
const Text(
  'Contact details unavailable — this order was placed before the app '
  'recorded them. Call the branch.',
),
```

The primary button comes from the pure rule, never from a hand-written switch in the widget:

```dart
final action = primaryActionFor(delivery);
if (action != null) {
  // FilledButton labelled action.label, calling the matching method on
  // riderTransitionController, then showing RiderRepositoryException.message
  // in a SnackBar when the database refuses.
}
```

- [ ] **Step 5: Delete the demo provider**

```bash
git rm lib/features/orders/providers/order_flow_provider.dart
```

- [ ] **Step 6: Run the whole suite**

Run: `flutter test && flutter analyze`
Expected: all pass, analyze clean.

- [ ] **Step 7: Commit**

```bash
git add -A lib/features/rider test/rider_dashboard_test.dart
git commit -m "replace the fake rider dashboard with one driven by rider_details and rider_assignments"
```

---

### Task 13: History and earnings screens

**Files:**
- Rewrite: `lib/features/rider/screens/rider_history_screen.dart`
- Rewrite: `lib/features/rider/screens/rider_earnings_screen.dart`
- Test: `test/rider_history_and_earnings_test.dart`

**Interfaces:**
- Consumes: `deliveredHistoryFor`, `earningsFor`, `completedCountFor` from Task 7; providers from Task 9
- Produces: the two screens created as placeholders in Task 11

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/theme/app_theme.dart';
import 'package:mrpizza/features/rider/data/rider_repository.dart';
import 'package:mrpizza/features/rider/models/rider_availability.dart';
import 'package:mrpizza/features/rider/models/rider_delivery.dart';
import 'package:mrpizza/features/rider/providers/rider_providers.dart';
import 'package:mrpizza/features/rider/screens/rider_earnings_screen.dart';
import 'package:mrpizza/features/rider/screens/rider_history_screen.dart';

class _FakeRiderRepository extends RiderRepository {
  _FakeRiderRepository({this.deliveries = const [], this.payoutRate = 250});

  final List<RiderDelivery> deliveries;
  final double payoutRate;

  @override
  Future<RiderDetails?> fetchRiderDetails() async => const RiderDetails(
        branchId: 'b1',
        availability: RiderAvailability.available,
        branchName: 'Abbottabad',
        branchAddress: 'Niazi Road',
      );

  @override
  Future<List<RiderDelivery>> fetchDeliveries() async => deliveries;

  @override
  Future<double> fetchPayoutRate() async => payoutRate;
}

RiderDelivery _delivery({
  required String status,
  String id = 'a',
  DateTime? deliveredAt,
}) =>
    RiderDelivery(
      assignmentId: id,
      orderId: 'o$id',
      billNumber: '#$id',
      assignmentStatus: status,
      customerName: 'Usama',
      customerPhone: '0300',
      deliveryAddress: 'Mandian',
      deliveryLatitude: 34.16,
      deliveryLongitude: 73.22,
      branchName: 'Abbottabad',
      branchAddress: 'Niazi Road',
      itemSummary: '1x Zinger',
      itemCount: 1,
      assignedAt: DateTime(2026, 9, 28, 10),
      pickedUpAt: null,
      deliveredAt: deliveredAt,
    );

Widget _app(_FakeRiderRepository repository, Widget child) => ProviderScope(
      overrides: [riderRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(theme: AppTheme.light, home: child),
    );

void main() {
  testWidgets('history lists finished deliveries and hides active ones',
      (tester) async {
    await tester.pumpWidget(_app(
      _FakeRiderRepository(deliveries: [
        _delivery(status: 'delivered', id: 'done',
            deliveredAt: DateTime(2026, 9, 28, 15)),
        _delivery(status: 'declined', id: 'no'),
        _delivery(status: 'accepted', id: 'live'),
      ]),
      const RiderHistoryScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('#done'), findsOneWidget);
    expect(find.text('#no'), findsOneWidget);
    expect(find.text('#live'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history says so when there is nothing yet', (tester) async {
    await tester.pumpWidget(
        _app(_FakeRiderRepository(), const RiderHistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('No completed deliveries'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('earnings shows the completed count times the configured rate',
      (tester) async {
    await tester.pumpWidget(_app(
      _FakeRiderRepository(
        deliveries: [
          _delivery(status: 'delivered', id: '1'),
          _delivery(status: 'delivered', id: '2'),
          _delivery(status: 'accepted', id: '3'),
        ],
      ),
      const RiderEarningsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('500'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('earnings says the rate is unavailable instead of showing zero',
      (tester) async {
    await tester.pumpWidget(_app(
      _FakeRiderRepository(
        deliveries: [_delivery(status: 'delivered')],
        payoutRate: 0,
      ),
      const RiderEarningsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('rate is unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/rider_history_and_earnings_test.dart`
Expected: FAIL — the placeholders do not read anything.

- [ ] **Step 3: Write the history screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';
import '../logic/delivery_actions.dart';
import '../providers/rider_providers.dart';

class RiderHistoryScreen extends ConsumerWidget {
  const RiderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveriesAsync = ref.watch(riderDeliveriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Deliveries')),
      body: deliveriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load your deliveries.'),
              TextButton(
                onPressed: () => ref.invalidate(riderDeliveriesProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (deliveries) {
          final history = deliveredHistoryFor(deliveries);
          if (history.isEmpty) {
            return const Center(child: Text('No completed deliveries yet'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: history.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final delivery = history[index];
              return MrCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(delivery.billNumber,
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(delivery.customerName,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Text(
                      delivery.assignmentStatus,
                      style: TextStyle(
                        color: delivery.assignmentStatus == 'delivered'
                            ? AppColors.success
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Write the earnings screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/widgets.dart';
import '../providers/rider_providers.dart';

class RiderEarningsScreen extends ConsumerWidget {
  const RiderEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rateAsync = ref.watch(payoutRateProvider);
    final earningsAsync = ref.watch(riderEarningsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Earnings')),
      body: earningsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const Center(
          child: Text('Could not load your earnings.'),
        ),
        data: (earnings) {
          final rate = rateAsync.valueOrNull ?? 0;
          if (rate <= 0) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Your payout rate is unavailable, so totals cannot be '
                  'shown. Ask the branch to confirm it.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const MrSectionTitle(title: 'Earnings so far'),
              const SizedBox(height: 14),
              MrCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rs. ${earnings.toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text('At Rs. ${rate.toStringAsFixed(0)} per delivery',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 5: Run and confirm green**

Run: `flutter test test/rider_history_and_earnings_test.dart && flutter analyze`
Expected: 4 tests pass, analyze clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/rider/screens/rider_history_screen.dart lib/features/rider/screens/rider_earnings_screen.dart test/rider_history_and_earnings_test.dart
git commit -m "add rider history and earnings screens that never invent a payout figure"
```

---

### Task 14: Role-aware drawer

**Files:**
- Modify: `lib/widgets/app_drawer.dart:143-200`
- Test: `test/role_aware_drawer_test.dart`

**Interfaces:**
- Consumes: `roleProvider` from `lib/core/providers/role_provider.dart`
- Produces: the customer tile list when the role is a customer, the rider tile list when it is a rider

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/core/providers/role_provider.dart';
import 'package:mrpizza/widgets/app_drawer.dart';

Widget _app(UserRole role) => ProviderScope(
      overrides: [roleProvider.overrideWith(() => _FixedRole(role))],
      child: const MaterialApp(
        home: Scaffold(body: AppDrawer()),
      ),
    );

class _FixedRole extends RoleNotifier {
  _FixedRole(this._role);
  final UserRole _role;

  @override
  UserRole build() => _role;
}

void main() {
  testWidgets('a rider sees deliveries, earnings and support', (tester) async {
    await tester.pumpWidget(_app(UserRole.rider));
    await tester.pumpAndSettle();

    expect(find.text('My Deliveries'), findsOneWidget);
    expect(find.text('My Earnings'), findsOneWidget);
    expect(find.text('Support Center'), findsOneWidget);
    expect(find.text('Loyalty Points'), findsNothing);
    expect(find.text('My Addresses'), findsNothing);
    expect(find.text('My Favourites'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a customer keeps the customer tiles', (tester) async {
    await tester.pumpWidget(_app(UserRole.customer));
    await tester.pumpAndSettle();

    expect(find.text('Loyalty Points'), findsOneWidget);
    expect(find.text('My Addresses'), findsOneWidget);
    expect(find.text('My Favourites'), findsOneWidget);
    expect(find.text('My Deliveries'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/role_aware_drawer_test.dart`
Expected: FAIL — the drawer shows the same tiles for everyone.

- [ ] **Step 3: Make the tile list depend on the role**

In `lib/widgets/app_drawer.dart`, add to the state class:

```dart
  final UserRole _role = ref.read(roleProvider);
```

and replace the hardcoded tile block with a role branch:

```dart
                  if (_role == UserRole.rider) ...[
                    _buildDrawerTile(
                      icon: Icons.delivery_dining_rounded,
                      title: 'My Deliveries',
                      onTap: () => _push(riderLandingLocation),
                    ),
                    _buildDrawerTile(
                      icon: Icons.payments_rounded,
                      title: 'My Earnings',
                      onTap: () => _push(riderEarningsLocation),
                    ),
                    _buildDrawerTile(
                      icon: Icons.headset_mic_rounded,
                      title: 'Support Center',
                      onTap: () => _push('/support'),
                    ),
                  ] else ...[
                    // the existing customer tiles, unchanged
                  ],
```

Add the imports:

```dart
import '../core/providers/role_provider.dart';
import '../core/routing/route_guard.dart';
```

Remove the triple-tap-to-`/rider` block (the `_versionTapCount` field, the `GestureDetector` around the version text, and its `onTap`) — the drawer entry and the route guard now cover rider access, and a hidden gesture is not a route.

- [ ] **Step 4: Run and confirm green**

Run: `flutter test test/role_aware_drawer_test.dart && flutter analyze`
Expected: 2 tests pass, analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/app_drawer.dart test/role_aware_drawer_test.dart
git commit -m "make the drawer role aware and drop the hidden triple tap rider entry"
```

---

### Task 15: Live updates for the rider dashboard

**Files:**
- Modify: `lib/features/rider/providers/rider_providers.dart`
- Test: `test/rider_realtime_test.dart`

**Interfaces:**
- Consumes: `riderRepositoryProvider` from Task 8, `RiderDelivery` from Task 6
- Produces: `riderDeliveriesProvider` as a `StreamProvider`, invalidated by the database on `rider_assignments` changes

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/rider/data/rider_repository.dart';
import 'package:mrpizza/features/rider/models/rider_delivery.dart';
import 'package:mrpizza/features/rider/providers/rider_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('the realtime channel is scoped to this rider own assignments', () {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
    );

    final channel = buildRiderAssignmentChannel(client, 'rider-uuid');

    // The filter is the security-relevant part: without it the client would
    // subscribe to every rider's assignments.
    expect(channel.payload, contains('rider_id=eq.rider-uuid'));
    expect(channel.payload, contains('event=INSERT'));
    expect(channel.payload, contains('event=UPDATE'));
    expect(channel.payload, contains('event=DELETE'));
  });
}
```

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/rider_realtime_test.dart`
Expected: FAIL — the builder does not exist.

- [ ] **Step 3: Write the channel builder**

In `lib/features/rider/providers/rider_providers.dart`:

```dart
import '../../../core/network/supabase_client.dart';
import 'dart:async';

/// Subscribes to changes on this rider's own assignments.
///
/// The `rider_id=eq.<uid>` filter is not an optimisation: without it the client
/// would receive every rider's assignments. RLS would still refuse to hand
/// over rows the caller cannot see, but the filter keeps the traffic honest.
RealtimeChannel buildRiderAssignmentChannel(
  SupabaseClient client,
  String riderId,
) {
  return client.channel('rider-assignments-$riderId').onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'rider_assignments',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'rider_id',
          value: riderId,
        ),
      );
}
```

- [ ] **Step 4: Turn the deliveries provider into a stream**

Replace the `FutureProvider` with a `StreamProvider` that re-reads on every
relevant change, and cancels the channel when nobody is listening:

```dart
/// The rider's assignments, re-read whenever the database says they changed.
///
/// This is live only while the app is open. A rider with the app closed is not
/// notified about a new assignment until they next open it; push notifications
/// are the fix for that and need a Firebase project.
final riderDeliveriesProvider = StreamProvider<List<RiderDelivery>>((ref) {
  final repository = ref.watch(riderRepositoryProvider);
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) {
    return Stream.value(const <RiderDelivery>[]);
  }

  final channel = buildRiderAssignmentChannel(repository.client, userId);
  ref.onDispose(() => repository.client.removeChannel(channel));

  return Stream<List<RiderDelivery>>.multi((controller) {
    Future<void> emit() async {
      try {
        controller.add(await repository.fetchDeliveries());
      } catch (error) {
        controller.addError(error);
      }
    }

    channel
      ..subscribe()
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'rider_assignments',
        callback: (_) => emit(),
      );

    emit();
    return channel.sink.close;
  });
});
```

Expose the client so the test and the provider can both reach it:

```dart
class RiderRepository {
  final SupabaseClient _client;

  RiderRepository({SupabaseClient? client}) : _client = client ?? supabase;

  /// The underlying client, so live subscriptions can be scoped to this rider.
  SupabaseClient get client => _client;
```

- [ ] **Step 5: Update the consumers of the old FutureProvider**

`riderEarningsProvider` and `riderDetailsProvider` read `riderDeliveriesProvider`
as a Future in Task 9. Change those to `await ref.watch(riderDeliveriesProvider.future)`
— a `StreamProvider` still exposes `.future` for the first value, so only the
call sites that need the *current* value need changing, not the API.

Run: `flutter analyze`
Expected: clean. If a call site breaks on `AsyncValue<List<RiderDelivery>>` versus
`AsyncValue<RiderAvailability>`, fix it by adding the `.future`.

- [ ] **Step 6: Run the whole suite**

Run: `flutter test && flutter analyze`
Expected: all pass, analyze clean.

- [ ] **Step 7: Commit**

```bash
git add lib/features/rider/providers/rider_providers.dart lib/features/rider/data/rider_repository.dart test/rider_realtime_test.dart
git commit -m "re-read rider deliveries on assignment changes instead of only on pull to refresh"
```

---

## Appendix: manual end-to-end check

Run after Task 4, then again after Task 15.

1. As a customer, place a delivery order. Confirm the new `orders` row has `customer_name`, `customer_phone` and `delivery_address` populated (only true after Task 10).
2. Ask the owner to insert a `rider_details` row for `rider@test.com` with a branch id. Until then the rider sees the setup message — that is correct, not a bug.
3. Sign in as the rider. Confirm the dashboard loads with real data and no demo names.
4. As the owner in the panel, assign the order to that rider. Confirm the dashboard shows the offer without a manual refresh.
5. Accept, then pick up, then deliver. After each step confirm `rider_assignments.status`, `orders.status` and `order_status_history` all agree.
6. Double-tap the final Deliver. Confirm exactly one `delivered` row in `order_status_history`.
7. Sign in as a customer and try `/rider/history`. Confirm the guard returns them to `/home`.
