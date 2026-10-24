-- ═══════════════════════════════════════════════════════════════════════════
-- Give a bill serial number back when its order is discarded.
--
-- Why this is needed:
--
-- Checkout has to insert the `orders` row BEFORE PayFast's page can open, because
-- `payfast-token` reads `orders.total` off that row — the amount must never come
-- from the phone. So every online payment attempt briefly owns a real order row,
-- and `orders_set_bill_serial_number` allocates the next per-branch number to it
-- on INSERT.
--
-- When a customer walks away from PayFast's page, `discard_unpaid_order` deletes
-- that row — which is correct, nothing was ordered. But the bill serial was a
-- SEQUENCE, and a sequence never rewinds. Every abandoned attempt therefore
-- burned a number permanently: the shop's counter sat at 73 while the newest
-- real order was ABT-071, because ABT-072 and ABT-073 belonged to two orders
-- that were created and then deleted inside the same checkout attempt.
--
-- A bill number the customer was never shown, never paid for, and never had a
-- receipt printed for it should not leave a hole in the shop's sequence. So the
-- number goes back when the order goes.
--
-- What is NOT changed:
--   * A number is only ever given back if it is still the NEWEST one. Once
--     another order has taken a later number, this one is left where it is —
--     rewinding past a number that a real order holds would hand two orders the
--     same bill number.
--   * Nothing about the payments, refunds or the paid-order refusals changes.
--     Every guard `discard_unpaid_order` already had is kept exactly as it was,
--     in the same order, and the rollback only runs after the delete succeeded.
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.discard_unpaid_order(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order     public.orders;
  v_serial    text;
  v_serial_no integer;
  v_prefix    text;
begin
  if p_order_id is null then
    return false;
  end if;

  select * into v_order
    from public.orders
   where id = p_order_id
     for update;

  if not found then
    return false;                      -- already gone, nothing to do
  end if;

  if v_order.customer_id is distinct from (select auth.uid()) then
    raise exception 'Order not found, or it is not yours'
      using errcode = 'P0002';
  end if;

  if v_order.payment_method is distinct from 'online' then
    raise exception 'Only an unpaid online order can be discarded'
      using errcode = 'P0002';
  end if;

  if v_order.payment_status = 'paid' then
    raise exception 'This order has been paid and cannot be discarded'
      using errcode = 'P0002';
  end if;

  -- Independent of the order column above. If PayFast's IPN landed a moment
  -- before this ran it wrote the payments row first, and that is the real
  -- evidence that money moved.
  if exists (
    select 1 from public.payments
     where order_id = p_order_id and status in ('paid', 'double_paid')
  ) then
    raise exception 'This order has a completed payment and cannot be discarded'
      using errcode = 'P0002';
  end if;

  -- Read before the delete. Afterwards there is no row left to read it from.
  v_serial := v_order.bill_serial_number;

  -- payments, transactions, voucher_redemptions and loyalty_ledger have no
  -- cascade from orders, so they are cleared explicitly.
  delete from public.payments         where order_id = p_order_id;
  delete from public.transactions     where order_id = p_order_id;
  delete from public.voucher_redemptions where order_id = p_order_id;
  delete from public.loyalty_ledger   where order_id = p_order_id;

  -- The loyalty trigger on `status` does not fire here (status is untouched),
  -- and the remaining children cascade.
  delete from public.orders where id = p_order_id;

  -- ── hand the bill number back ──────────────────────────────────────────
  --
  -- Deliberately narrow. `next_bill_serial_number()` builds the serial as
  -- <BRANCH CODE>-<number>, so anything that does not match that shape was not
  -- allocated by the counter and must not touch it.
  if v_serial is not null and v_serial ~ '^[A-Za-z0-9]+-[0-9]+$' then
    v_serial_no := split_part(v_serial, '-', 2)::integer;

    -- The same prefix expression `next_bill_serial_number()` uses, so the two
    -- can never disagree about which numbers this counter owns.
    select coalesce(
             nullif(
               upper(regexp_replace(coalesce(b.code, ''), '[^A-Za-z0-9]', '', 'g')),
               ''
             ),
             'BILL'
           )
      into v_prefix
      from public.branches b
     where b.id = v_order.branch_id;

    update public.bill_serial_counters c
       set last_number = greatest(v_serial_no - 1, 0)
     where c.branch_id = v_order.branch_id
       -- Only the number this order just held can be released.
       and c.last_number = v_serial_no
       -- And only if it is genuinely this counter's number, not a legacy serial
       -- that happens to sit on the row.
       and split_part(v_serial, '-', 1) = v_prefix
       -- Belt and braces against the unique index on bill_serial_number: if any
       -- other order somehow holds this serial, the counter must not reissue it.
       and not exists (
         select 1
           from public.orders o
          where o.branch_id = c.branch_id
            and o.bill_serial_number = v_serial
       );
  end if;

  return true;
end;
$$;

comment on function public.discard_unpaid_order(uuid) is
  'Removes an unpaid online order and releases the bill serial it was allocated, '
  'so an abandoned payment attempt does not leave a hole in the branch sequence.';


-- ═══════════════════════════════════════════════════════════════════════════
-- One-time reconciliation: close the holes already left by discarded attempts.
--
-- Scoped to each branch's OWN prefix rather than "the highest number in
-- `orders`". Abbottabad carries a legacy `TEST-857119` row from before the
-- counter existed, and an unscoped max would have pushed the counter to
-- 857120 instead of 71.
--
-- Only ever LOWERS a counter, never raises one: a counter that is ahead of its
-- orders is exactly the state being repaired, and one that is behind is left
-- alone so this can never cause a collision by rewinding past a live number.
-- ═══════════════════════════════════════════════════════════════════════════

with target as (
  select
    c.branch_id,
    greatest(
      coalesce(
        (
          select max(split_part(o.bill_serial_number, '-', 2)::integer)
            from public.orders o
            join public.branches b on b.id = o.branch_id
           where o.branch_id = c.branch_id
             and o.bill_serial_number ~ '^[A-Za-z0-9]+-[0-9]+$'
             and split_part(o.bill_serial_number, '-', 1) = coalesce(
                   nullif(
                     upper(regexp_replace(coalesce(b.code, ''), '[^A-Za-z0-9]', '', 'g')),
                     ''
                   ),
                   'BILL'
                 )
        ),
        0
      ),
      0
    ) as last_number
  from public.bill_serial_counters c
)
update public.bill_serial_counters c
   set last_number = t.last_number
  from target t
 where c.branch_id = t.branch_id
   and c.last_number > t.last_number;

-- What the next order at each branch will be numbered.
select
  b.code,
  c.last_number,
  b.code || '-' || lpad((c.last_number + 1)::text, 3, '0') as next_bill_number
from public.bill_serial_counters c
join public.branches b on b.id = c.branch_id
order by b.code;