-- One saving per order, enforced by the database.
--
-- Three things can discount an order today:
--   * a voucher                    -> redeem_voucher
--   * loyalty points               -> redeem_loyalty_points
--   * the first-order welcome offer -> apply_first_order_discount
--
-- All three write to `orders.discount_amount`, and none of them could see the
-- others. redeem_voucher set `discount_amount = v_amount` outright, so a voucher
-- taken after a points spend silently erased the points saving off the bill
-- while the ledger kept the debit. The app sequenced them around this, but
-- sequencing a client's requests is not a rule — any other client, or the same
-- client reordered, gets a different answer.
--
-- `orders.discount_amount_source` makes the choice a property of the row instead
-- of a property of the order the requests arrived in. Each function reads it
-- first and refuses if another saving is already recorded, so exactly one can
-- ever land, whoever calls and in whatever order.
--
-- Existing rows are backfilled from what is already there: a row with a
-- non-zero discount was either a voucher or points, and the ledger is the only
-- thing that can tell those apart.

alter table public.orders
  add column if not exists discount_amount_source text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'orders_discount_amount_source_check'
  ) then
    alter table public.orders
      add constraint orders_discount_amount_source_check
      check (
        discount_amount_source is null
        or discount_amount_source in ('first_order', 'voucher', 'loyalty_points')
      );
  end if;
end;
$$;

comment on column public.orders.discount_amount_source is
  'Which saving produced orders.discount_amount: first_order, voucher or loyalty_points. '
  'Null when the order carries no discount. Set by redeem_voucher, redeem_loyalty_points and '
  'apply_first_order_discount; each refuses an order that already has another source, so an '
  'order can never carry two savings.';

-- Backfill: a voucher redemption row means voucher, otherwise points.
update public.orders o
   set discount_amount_source = case
         when exists (
           select 1 from public.voucher_redemptions r
            where r.order_id = o.id
         ) then 'voucher'
         else 'loyalty_points'
       end
 where coalesce(o.discount_amount, 0) > 0
   and o.discount_amount_source is null;