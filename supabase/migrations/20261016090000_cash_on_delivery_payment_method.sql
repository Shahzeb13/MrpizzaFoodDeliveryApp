-- ═══════════════════════════════════════════════════════════════════════════
-- Cash on Delivery: record how an order is being paid, and let the rider close
-- it out when the money changes hands.
--
-- Why this is needed: before it, a cash order sat at payment_status = 'pending'
-- forever, which is indistinguishable from an online payment the customer
-- abandoned. Neither the branch nor the rider could tell "will pay on delivery"
-- apart from "started paying and walked away", so nobody could chase either one.
--
-- Two things are added, and nothing existing is altered:
--
--   * orders.payment_method  -- nullable, so the 35 existing orders are untouched
--   * mark_cash_collected()  -- the only supported way to settle a cash order
--
-- The column is deliberately nullable rather than defaulted. A default of 'cod'
-- would silently relabel every existing online order that had not been paid yet
-- as cash on delivery, which is a different promise to the customer.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.orders
  add column if not exists payment_method text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_payment_method_check'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders
      add constraint orders_payment_method_check
      check (payment_method is null or payment_method in ('cod', 'online'));
  end if;
end;
$$;

comment on column public.orders.payment_method is
  'How this order is being paid. NULL on orders placed before cash on delivery existed.';

-- ═══════════════════════════════════════════════════════════════════════════
-- Settles a cash order.
--
-- SECURITY DEFINER because the rider authenticates as a plain `authenticated`
-- user and the orders table is not something they are granted direct writes on.
-- Refuses anything that is not an unsettled cash order, so it cannot be used to
-- mark an online payment as collected, to double-collect, or to settle an order
-- the rider has nothing to do with.
--
-- Returns the order row on success.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.mark_cash_collected(p_order_id uuid)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_rider uuid := (select auth.uid());
begin
  if p_order_id is null then
    raise exception 'An order id is required'
      using errcode = 'P0002';
  end if;

  if not public.is_staff() then
    raise exception 'Only branch staff or a rider can mark a cash order collected'
      using errcode = '42501';
  end if;

  select * into v_order
    from public.orders o
   where o.id = p_order_id
     and (
       o.rider_id = v_rider
       or public.my_branch_id() = o.branch_id
       or public.is_owner()
     )
     for update;

  if not found then
    raise exception 'Order not found, or it is not one of yours'
      using errcode = 'P0002';
  end if;

  if v_order.payment_method is distinct from 'cod' then
    raise exception 'This order was not placed as cash on delivery'
      using errcode = 'P0002';
  end if;

  if v_order.payment_status = 'paid' then
    raise exception 'This order is already marked as paid'
      using errcode = 'P0002';
  end if;

  -- Only settles an order the rider actually turned up for. Without this a cash
  -- order could be marked collected the moment it was placed, from the shop.
  if v_order.status not in ('out_for_delivery', 'delivered') then
    raise exception 'This order has not been dispatched yet'
      using errcode = 'P0002';
  end if;

  update public.orders
     set payment_status = 'paid'
   where id = p_order_id
   returning * into v_order;

  return v_order;
end;
$$;

revoke all on function public.mark_cash_collected(uuid) from public, anon, authenticated;
grant execute on function public.mark_cash_collected(uuid) to authenticated, service_role;

comment on function public.mark_cash_collected(uuid) is
  'Marks a dispatched cash-on-delivery order as paid. Refused for online orders.';
