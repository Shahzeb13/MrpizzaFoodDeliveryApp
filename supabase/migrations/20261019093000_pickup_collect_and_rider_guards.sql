-- ═══════════════════════════════════════════════════════════════════════════
-- Pickup orders: close one out in a single click, and keep riders out of them.
--
-- `order_type = 'pickup'` has been stored since long before this, and the app has
-- been able to place one since long before this. Nothing downstream ever used
-- it, which left three specific holes:
--
--   1. A cash pickup order could not be marked paid in the same moment the
--      customer paid at the counter. `mark_cash_collected` demands the order be
--      `out_for_delivery` or `delivered`; a pickup order is never
--      `out_for_delivery` because it has no rider. Doing it as two separate
--      actions is how a shop ends up holding cash the ledger says is still owed.
--
--   2. Nothing stopped a pickup order being moved into `out_for_delivery`, or
--      from being handed to a rider. If that happened it appeared in the
--      rider's delivery list and told the customer a rider was on the way.
--
--   3. `order_status_history` is written only by the rider functions, so a
--      pickup order has no timeline at all unless the branch records its moves.
--
-- What is added, and nothing existing is altered:
--
--   * collect_pickup_order()  -- one button: collected AND paid, atomically
--   * two guards               -- a pickup order never gets a rider
--
-- `delivered` is reused as "collected" rather than adding a status. The loyalty
-- trigger already fires on `delivered`, so loyalty points land the moment the
-- customer takes the order away, and no consumer of `orders.status` has to learn
-- a seventh value.
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- Collect a pickup order.
--
-- SECURITY DEFINER because branch staff authenticate as a plain `authenticated`
-- user and are not granted direct writes on `orders`.
--
-- Records the status history itself, because `rider_complete_delivery` is the
-- only thing currently writing that table and a pickup order has no rider.
--
-- Returns the order row on success.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.collect_pickup_order(p_order_id uuid)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
begin
  if p_order_id is null then
    raise exception 'An order id is required'
      using errcode = 'P0002';
  end if;

  if not public.is_staff() then
    raise exception 'Only branch staff can collect a pickup order'
      using errcode = '42501';
  end if;

  select * into v_order
    from public.orders o
   where o.id = p_order_id
     for update;

  if not found then
    raise exception 'Order not found'
      using errcode = 'P0002';
  end if;

  if public.my_branch_id() is distinct from v_order.branch_id
     and not public.is_owner() then
    raise exception 'That order belongs to another branch'
      using errcode = '42501';
  end if;

  if v_order.order_type is distinct from 'pickup' then
    raise exception 'This is a delivery order. A rider completes it instead.'
      using errcode = 'P0002';
  end if;

  if v_order.status = 'cancelled' then
    raise exception 'This order was cancelled'
      using errcode = 'P0002';
  end if;

  if v_order.status = 'delivered' then
    raise exception 'This order has already been collected'
      using errcode = 'P0002';
  end if;

  -- An online order is only ever marked paid by PayFast's IPN. Collecting it
  -- anyway would let the shop hand over food against a payment that never
  -- arrived, so this refuses rather than quietly writing 'paid'.
  if v_order.payment_method is distinct from 'cod'
     and v_order.payment_status is distinct from 'paid' then
    raise exception 'This order has not been paid. Check the PayFast payment before collecting it.'
      using errcode = 'P0002';
  end if;

  -- Cash changes hands at the counter in the same moment the food does, so both
  -- are written in one statement. Two separate actions is exactly how a shop
  -- ends up holding cash the ledger still says is owed.
  if v_order.payment_method = 'cod' then
    update public.orders
       set status         = 'delivered',
           payment_status = 'paid'
     where id = p_order_id
     returning * into v_order;
  else
    update public.orders
       set status = 'delivered'
     where id = p_order_id
     returning * into v_order;
  end if;

  insert into public.order_status_history (order_id, status, changed_by)
  values (p_order_id, 'delivered', (select auth.uid()));

  return v_order;
end;
$$;

revoke all on function public.collect_pickup_order(uuid) from public, anon, authenticated;
grant execute on function public.collect_pickup_order(uuid) to authenticated, service_role;

comment on function public.collect_pickup_order(uuid) is
  'Closes out a pickup order in one action: marks it delivered (collected) and, '
  'for a cash order, marks it paid in the same statement. Branch staff only.';


-- ═══════════════════════════════════════════════════════════════════════════
-- Guard: a pickup order never enters a rider stage.
--
-- A BEFORE trigger, so it fires whatever gets there — the admin panel, a
-- support engineer, or anyone else with write access. A pickup order has no
-- rider and nothing to deliver, and `out_for_delivery` is the one status that
-- makes the customer app promise a rider who does not exist.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.orders_pickup_never_gets_a_rider()
returns trigger
language plpgsql
as $$
begin
  if new.order_type = 'pickup'
     and new.status is distinct from old.status
     and new.status = 'out_for_delivery' then
    raise exception 'Order % is a pickup order. It is collected at the counter, never sent out for delivery.', old.id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'trg_orders_pickup_never_gets_a_rider'
      and tgrelid = 'public.orders'::regclass
  ) then
    create trigger trg_orders_pickup_never_gets_a_rider
      before update of status on public.orders
      for each row
      execute function public.orders_pickup_never_gets_a_rider();
  end if;
end;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- Guard: a pickup order never gets a rider assigned.
--
-- Without this, an assignment slips through and `rider_deliveries()` lists it —
-- the rider is handed a job with no address to go to, and the customer's
-- tracking screen shows a rider who is never going to arrive.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.pickup_orders_get_no_rider()
returns trigger
language plpgsql
as $$
declare
  v_order_type text;
begin
  select o.order_type into v_order_type
    from public.orders o
   where o.id = new.order_id;

  if v_order_type = 'pickup' then
    raise exception 'Order % is a pickup order. It has no rider and no delivery address.', new.order_id
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_trigger
    where tgname = 'trg_pickup_orders_get_no_rider'
      and tgrelid = 'public.rider_assignments'::regclass
  ) then
    create trigger trg_pickup_orders_get_no_rider
      before insert on public.rider_assignments
      for each row
      execute function public.pickup_orders_get_no_rider();
  end if;
end;
$$;