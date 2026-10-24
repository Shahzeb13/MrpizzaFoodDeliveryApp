-- ═══════════════════════════════════════════════════════════════════════════
-- PayFast: many payment attempts per order.
--
-- One order can have MANY payment attempts — the customer retries, switches
-- wallet, or the WebView closes. Every attempt is its own row in `payments`
-- with its own `basket_id`.
--
-- Replaces the single-attempt model from 20261014090000_payfast_payments.sql,
-- which made retry structurally impossible: `basket_id` was the primary key,
-- so a second attempt could not even be inserted, and `apply_payment_result`
-- returned 'duplicate' for any IPN once status left 'pending'.
--
-- Schema assumptions versus this database's `public.orders`:
--
--   assumed                        actual
--   -----------------------------  ------------------------------------------
--   orders.id uuid                 matches (uuid, gen_random_uuid())
--   orders.user_id uuid            orders.customer_id uuid -> profiles(id).
--                                  Named in a comment only, never queried.
--   orders.total numeric           matches (numeric not null)
--   orders.payment_status text     added by the previous migration; already
--                                  present, so this file does not touch it.
--
-- `orders` is already in `supabase_realtime` (rider panel), so the publication
-- line in the reference would abort the whole migration. Guarded below.
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- Attempt ledger.
--
-- `basket_id` stays the primary key: it is what goes to PayFast and what comes
-- back in the IPN, so it must be globally unique. Distinct attempts therefore
-- must be given distinct baskets by whatever starts the checkout — that is the
-- caller's job, and it is why retrying on the same basket cannot work.
--
-- `amount` is captured server-side and is the only figure an IPN is checked
-- against. Nothing here ever trusts an amount from a callback or a client.
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.payments (
  basket_id      text primary key,               -- sent to PayFast, comes back in the IPN
  order_id       uuid not null references public.orders(id),
  amount         numeric(12,2) not null,         -- server-calculated, source of truth
  status         text not null default 'pending'
                 check (status in ('pending', 'paid', 'failed', 'double_paid')),
  transaction_id text,
  err_code       text,
  created_at     timestamptz not null default now(),
  paid_at        timestamptz
);

create index if not exists payments_order_id_idx on public.payments(order_id);

-- The previous migration already created this table with a narrower CHECK that
-- omitted 'double_paid'. `create table if not exists` is a silent no-op when the
-- table is present, so the old constraint would survive and reject every
-- double payment. Swapping the constraint is the fix; the table itself is kept
-- so grants and comments on it are not thrown away with a drop.
alter table public.payments drop constraint if exists payments_status_check;

alter table public.payments
  add constraint payments_status_check
  check (status in ('pending', 'paid', 'failed', 'double_paid'));

-- ═══════════════════════════════════════════════════════════════════════════
-- At most ONE paid attempt per order, enforced by the database itself.
--
-- 'double_paid' is deliberately outside the predicate. The function needs to be
-- able to write that second successful row before anything is refunded, and it
-- could not do so if this index also covered it.
-- ═══════════════════════════════════════════════════════════════════════════

create unique index if not exists payments_one_paid_per_order
  on public.payments(order_id) where status = 'paid';

-- No policies on purpose: only the service role (Edge Functions) touches this
-- table. service_role carries BYPASSRLS; anon and authenticated match zero
-- policies and see nothing.
alter table public.payments enable row level security;

comment on table public.payments is
  'PayFast payment attempts, one row per attempt. Many rows per order; at most one may be status=paid.';

-- ═══════════════════════════════════════════════════════════════════════════
-- Applies an IPN result. Safe against duplicate IPNs, a failed attempt that is
-- later paid on the same basket, and a late success arriving for an attempt of
-- an order that was already paid by another one.
--
-- Returns: unknown_basket | duplicate | amount_mismatch | paid | double_paid | failed
--
-- Only the 'paid' branch writes to `orders`. A failed attempt never fails the
-- order, and a double payment never changes it either -- the order is paid, it
-- simply also needs refunding.
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

  -- paid is final. failed is NOT final: the customer may retry on the same page.
  if v.status in ('paid', 'double_paid') then
    return 'duplicate';
  end if;

  if p_err = '000' then
    if p_paid is null or p_paid <> v.amount then
      return 'amount_mismatch';           -- leave as is, investigate manually
    end if;

    -- Another attempt for this order already succeeded: money moved twice.
    if exists (select 1 from public.payments
                where order_id = v.order_id
                  and status = 'paid'
                  and basket_id <> p_basket) then
      update public.payments
         set status = 'double_paid', transaction_id = p_txn,
             err_code = p_err, paid_at = now()
       where basket_id = p_basket;
      return 'double_paid';               -- needs a refund
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
  return 'failed';
end;
$$;

revoke all on function public.apply_payment_result(text, text, text, numeric)
  from public, anon, authenticated;
grant execute on function public.apply_payment_result(text, text, text, numeric) to service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- Realtime.
--
-- `orders` is already a member of supabase_realtime, and a bare ADD TABLE raises
-- "table is already member of publication", aborting the migration. Guarded so
-- the statement is a no-op when it is already there.
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