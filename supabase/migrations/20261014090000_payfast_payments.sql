-- ═══════════════════════════════════════════════════════════════════════════
-- PayFast checkout: per-basket payment ledger + idempotent IPN result applier.
--
-- Adapted from the vendor reference (001_payments.sql) to this schema. What the
-- reference assumed versus what `public.orders` actually holds:
--
--   assumed                        actual
--   -----------------------------  ------------------------------------------
--   orders.id uuid                 matches (uuid, gen_random_uuid())
--   orders.user_id uuid            orders.customer_id uuid -> profiles(id).
--                                  The reference only names user_id in a comment,
--                                  never in a query, so nothing had to be
--                                  rewritten; recorded here so the next reader
--                                  does not go looking for `user_id`.
--   orders.total numeric           matches (numeric not null)
--   orders.payment_status text     DID NOT EXIST. Added below.
--
-- Two further things the reference would have tripped over if run verbatim:
--
--   * `alter publication supabase_realtime add table orders` raises
--     "table is already member of publication" -- `orders` has been in the
--     realtime publication since the rider panel shipped. Guarded now.
--   * `orders.status` is already taken, and it means kitchen/delivery progress
--     (confirmed, in_kitchen, ready_for_pickup, out_for_delivery, delivered,
--     cancelled). Payment state gets its own `payment_status` so the two can
--     never be read as one.
--
-- The basket id sent to PayFast and echoed back in the IPN is
-- `orders.bill_serial_number` (text, unique). That value is what `payments.
-- basket_id` holds -- it is not `orders.id`.
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- Payment state on the order itself.
--
-- NOT NULL with a default so the existing rows backfill to 'pending' in place;
-- PostgreSQL 11+ does that without rewriting the table. The constraint is
-- added separately because `add column if not exists` skips the entire clause
-- when the column is already there, which would silently drop the check on a
-- re-run.
-- ═══════════════════════════════════════════════════════════════════════════

alter table public.orders
  add column if not exists payment_status text not null default 'pending';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'orders_payment_status_check'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders
      add constraint orders_payment_status_check
      check (payment_status in ('pending', 'paid', 'failed'));
  end if;
end;
$$;

comment on column public.orders.payment_status is
  'Payment state for this order. Distinct from orders.status, which tracks kitchen and delivery progress.';

-- ═══════════════════════════════════════════════════════════════════════════
-- One row per basket, written when checkout starts.
--
-- `amount` is copied in server-side and is the value the IPN is checked against;
-- the figure in the callback is never trusted on its own.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.payments (
  basket_id      text primary key,               -- sent to PayFast, comes back in the IPN
  order_id       uuid not null references public.orders(id),
  amount         numeric(12,2) not null,         -- server-calculated, source of truth
  status         text not null default 'pending'
                 check (status in ('pending', 'paid', 'failed')),
  transaction_id text,
  err_code       text,
  created_at     timestamptz not null default now(),
  paid_at        timestamptz
);

create index if not exists payments_order_id_idx on public.payments(order_id);

comment on table public.payments is
  'PayFast baskets. amount is captured server-side and is the only figure an IPN is validated against.';

-- No policies on purpose: only the service role (Edge Functions) touches this
-- table. service_role carries BYPASSRLS, so it reads and writes regardless,
-- while anon and authenticated match zero policies and see nothing.
alter table public.payments enable row level security;

-- ═══════════════════════════════════════════════════════════════════════════
-- Applies an IPN result exactly once. The row lock plus the status check make
-- a replayed or duplicated IPN harmless.
--
-- Returns: unknown_basket | duplicate | amount_mismatch | paid | failed
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.apply_payment_result(
  p_basket text,
  p_err    text,
  p_txn    text,
  p_paid   numeric
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.payments%rowtype;
begin
  select * into v from public.payments where basket_id = p_basket for update;

  if not found then
    return 'unknown_basket';
  end if;

  if v.status <> 'pending' then
    return 'duplicate';
  end if;

  if p_err = '000' then
    if p_paid is null or p_paid <> v.amount then
      return 'amount_mismatch';           -- leave pending, investigate manually
    end if;

    update public.payments
       set status = 'paid', transaction_id = p_txn, err_code = p_err, paid_at = now()
     where basket_id = p_basket;

    update public.orders set payment_status = 'paid' where id = v.order_id;
    return 'paid';
  end if;

  update public.payments
     set status = 'failed', transaction_id = p_txn, err_code = p_err
   where basket_id = p_basket;

  update public.orders set payment_status = 'failed' where id = v.order_id;
  return 'failed';
end;
$$;

-- The reference only failed the payments row and left the order untouched, so a
-- declined attempt never showed up on the order the customer was watching.
-- The orders write is what the app's realtime subscription reads.

revoke all on function public.apply_payment_result(text, text, text, numeric)
  from public, anon, authenticated;
grant execute on function public.apply_payment_result(text, text, text, numeric) to service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- Realtime.
--
-- `orders` is already a member of supabase_realtime (rider panel), so a bare
-- ADD TABLE aborts the whole migration. Guarded instead of dropped: adding the
-- table again is harmless, but adding it when it is absent is not optional.
-- ═══════════════════════════════════════════════════════════════════════════

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'orders'
  ) then
    alter publication supabase_realtime add table public.orders;
  end if;
end;
$$;
