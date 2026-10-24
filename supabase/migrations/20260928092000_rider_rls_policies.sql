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

-- Constrain what a customer may create, not just whose order it is. The
-- publishable key ships inside the APK, so without this a modified app could
-- insert a zero-total order, or one already marked delivered.
drop policy if exists "orders customer creates own" on public.orders;
create policy "orders customer creates own"
  on public.orders for insert to authenticated
  with check (
    customer_id = (select auth.uid())
    and status = 'confirmed'
    and coalesce(subtotal, 0) >= 0
    and coalesce(tax, 0) >= 0
    and coalesce(delivery_charges, 0) >= 0
    and coalesce(discount_amount, 0) >= 0
    and coalesce(total, 0) = coalesce(subtotal, 0)
                       + coalesce(tax, 0)
                       + coalesce(delivery_charges, 0)
                       - coalesce(discount_amount, 0)
  );

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
-- The panel still needs UPDATE: an owner must be able to correct a rider stuck
-- on 'on_delivery', move a rider between branches, or take one offline.
drop policy if exists "rider_details staff updates" on public.rider_details;
create policy "rider_details staff updates"
  on public.rider_details for update to authenticated
  using (public.is_staff())
  with check (public.is_staff());

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
-- complete / fail are the only paths a rider has. The panel can UPDATE, because
-- reassigning a delivery is a real thing an owner has to do.
drop policy if exists "rider_assignments staff updates" on public.rider_assignments;
create policy "rider_assignments staff updates"
  on public.rider_assignments for update to authenticated
  using (public.is_staff())
  with check (public.is_staff());

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

-- ═══════════════════════════════════════════════════════════════════════════
-- Security follow-ups found while auditing the above.
--
-- These are not rider-panel behaviour; they are the same class of leak, and
-- each one is exploitable with nothing but the publishable key that ships in
-- the APK.
-- ═══════════════════════════════════════════════════════════════════════════

-- ------------------------------------------------------------- profiles
-- The existing policy is granted to PUBLIC with the qual
--   auth.role() = 'authenticated' AND role = 'rider'
-- so ANY signed-in customer can list every rider's name, phone and branch.
-- Reading a rider's profile is a staff job (the panel lists riders); the
-- customer app reaches a rider only through the SECURITY DEFINER
-- order_tracking()/rider_deliveries() functions, which already scope the row.
drop policy if exists "Staff can read rider profiles" on public.profiles;
drop policy if exists "staff read rider profiles" on public.profiles;
create policy "staff read rider profiles"
  on public.profiles for select to authenticated
  using (public.is_staff() and role = 'rider');

-- ------------------------------------------------------ table privileges
-- RLS plus a matching policy is the real gate, but the publishable key holds
-- table-level grants on these tables too. Take the grants away from anon so
-- a future policy mistake cannot reopen the hole. `authenticated` keeps its
-- grants for the panel; the policies above decide what each role may touch.
--
-- branches is the one exception: the customer app reads branches before it
-- has a session, so anon keeps SELECT and nothing else.
revoke all on public.orders               from anon;
revoke all on public.order_items          from anon;
revoke all on public.order_status_history from anon;
revoke all on public.rider_assignments    from anon;
revoke all on public.rider_details        from anon;
revoke all on public.transactions         from anon;
revoke all on public.branches             from anon;
grant select on public.branches to anon;

-- ------------------------------------------------------- function grants
-- rider_deliveries() was executable by PUBLIC. It returns nothing when
-- auth.uid() is null, but it must not be callable without a rider session.
revoke all on function public.rider_deliveries(integer, integer, boolean)
  from public, anon;
grant execute on function public.rider_deliveries(integer, integer, boolean)
  to authenticated, service_role;

-- loyalty_demo_simulation() is a SECURITY DEFINER test harness that inserts,
-- updates and deletes rows in orders and loyalty_ledger, and even rewrites
-- request.jwt.claims to impersonate a customer. It had no reason to be
-- callable by a client at all.
revoke all on function public.loyalty_demo_simulation(boolean)
  from public, anon, authenticated;
grant execute on function public.loyalty_demo_simulation(boolean)
  to service_role;

-- These functions all act on auth.uid() and are only reachable after checkout,
-- which the router guards behind a session. An anon caller has no legitimate
-- use for any of them, and validate_voucher()/redeem_voucher() accept a
-- p_user_id that must never be supplied by an anonymous client.
revoke all on function public.validate_voucher(text, numeric, uuid, uuid[], uuid)
  from public, anon;
grant execute on function public.validate_voucher(text, numeric, uuid, uuid[], uuid)
  to authenticated, service_role;

revoke all on function public.redeem_voucher(text, uuid, uuid)
  from public, anon;
grant execute on function public.redeem_voucher(text, uuid, uuid)
  to authenticated, service_role;

revoke all on function public.first_order_offer(numeric, uuid)
  from public, anon;
grant execute on function public.first_order_offer(numeric, uuid)
  to authenticated, service_role;

revoke all on function public.apply_first_order_discount(uuid)
  from public, anon;
grant execute on function public.apply_first_order_discount(uuid)
  to authenticated, service_role;

revoke all on function public.get_my_loyalty_balance()
  from public, anon;
grant execute on function public.get_my_loyalty_balance()
  to authenticated, service_role;

revoke all on function public.customer_branch_id(uuid)
  from public, anon;
grant execute on function public.customer_branch_id(uuid)
  to authenticated, service_role;
