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

-- The rider's own assignments, joined to the order contact snapshot and the
-- branch. Read-only: this is the only read a rider makes on their work, and it
-- is scoped to the signed-in rider in the WHERE clause rather than relying on
-- the caller's RLS.
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
      select string_agg(oi.quantity || 'x ' || mi.name, ', ' order by mi.name)
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
