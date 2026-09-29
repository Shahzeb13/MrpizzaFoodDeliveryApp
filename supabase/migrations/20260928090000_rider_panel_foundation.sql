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

-- Why a delivery could not be completed. Without this, rider_fail_delivery had
-- nowhere to put the rider's explanation and the shop never learned why.
alter table public.rider_assignments
  add column if not exists failure_reason text;

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
