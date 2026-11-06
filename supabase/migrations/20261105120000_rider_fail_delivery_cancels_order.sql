-- A rider's "Report a problem" ends the order.
--
-- ABT-089 exposed both halves of this: the rider app recorded the failure
-- ("Customer refused the order"), but `rider_fail_delivery` handed the order
-- back to the queue as `confirmed` — so the branch saw a dead delivery come
-- back to life as a fresh New Order, and nothing told the rider they had
-- actually been handed the work.
--
-- The fix has two halves, in one migration on purpose so the app and the
-- board change together:
--
-- 1. `rider_fail_delivery` cancels the order (with the rider's reason on
--    `orders.cancel_reason`) instead of resetting it to `confirmed`, and
--    frees the rider the same way a completed delivery does.
-- 2. A new trigger pushes the *rider* a notification the moment the panel
--    inserts their assignment — the `rider_assignments` insert was the only
--    step of the dispatch chain that never called the push function.

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
  v_order_status text;
  v_reason text;
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

  select o.status into v_order_status
    from public.orders o
   where o.id = v_row.order_id
     for update;

  -- A dead order (cancelled / delivered) or an unsent one cannot fail.
  if v_order_status is distinct from 'confirmed'
     and v_order_status is distinct from 'in_kitchen'
     and v_order_status is distinct from 'ready_for_pickup'
     and v_order_status is distinct from 'out_for_delivery' then
    raise exception 'This order is no longer being delivered'
      using errcode = 'P0002';
  end if;

  perform 1 from public.rider_details
   where profile_id = v_row.rider_id
   for update;

  v_reason := nullif(trim(coalesce(p_reason, '')), '');

  update public.rider_assignments
     set status         = 'failed',
         failure_reason = v_reason
   where id = v_row.id
   returning * into v_row;

  -- The rider's report ends the order. `cancelled` is the terminal state the
  -- board already owns (`trg_orders_cancelled_is_final` keeps it closed), so
  -- the order may never reappear as a fresh New Order on the panel.
  update public.orders
     set status        = 'cancelled',
         cancel_reason = coalesce(v_reason, 'Rider reported a delivery problem')
   where id = v_row.order_id;

  insert into public.order_status_history (order_id, status, changed_by)
  values (v_row.order_id, 'cancelled', (select auth.uid()));

  -- Free the rider the same way a completed delivery does: their report was
  -- received, they take the next job. A rider who went offline mid-shift
  -- stays offline instead of being silently put back online.
  update public.rider_details
     set status = case when status = 'offline' then 'offline' else 'available' end
   where profile_id = v_row.rider_id;

  return v_row;
end;
$$;

-- Rider-side push for a new assignment.
--
-- The panel inserts `rider_assignments(status='assigned')` from its assigner;
-- historically only the rider app's *own* transitions called
-- `send-push-notification`, so the one event a rider is actually waiting for
-- — an order being offered to them — came with no notification at all. This
-- trigger reuses the exact mechanism the customer-status trigger uses:
-- `pg_net` posting to the same Edge Function, with the rider's own user id
-- so the function multicasts to their FCM token rows.
--
-- It fires on INSERT only. Every assignment row is born `assigned`; the
-- later lifecycle (accepted / picked_up / delivered / failed) is announced
-- from the rider's own transitions or the order-status trigger.

create or replace function public.notify_rider_on_assignment()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_rider_user_id uuid;
begin
  if new.status is distinct from 'assigned' then
    return new;
  end if;

  select profile_id into v_rider_user_id
    from public.rider_details
   where profile_id = new.rider_id;

  if v_rider_user_id is null then
    return new;
  end if;

  perform net.http_post(
    url := 'https://eytsownrsujphibqpimt.supabase.co/functions/v1/send-push-notification',
    body := jsonb_build_object(
      'user_id', v_rider_user_id,
      'title', 'New delivery order',
      'body', 'A new delivery was assigned to you. Open the app to accept it.',
      'data', jsonb_build_object(
        'type', 'rider_assignment',
        'assignment_id', new.id,
        'order_id', new.order_id
      )
    ),
    headers := '{"Content-Type": "application/json"}'::jsonb
  );

  return new;
end;
$$;

drop trigger if exists trg_notify_rider_on_assignment on public.rider_assignments;

create trigger trg_notify_rider_on_assignment
after insert on public.rider_assignments
for each row execute function public.notify_rider_on_assignment();

-- Same hygiene as the other rider functions: the trigger function itself
-- stays server-side business, not something an anon caller can invoke.
revoke execute on function public.notify_rider_on_assignment() from public, anon;
