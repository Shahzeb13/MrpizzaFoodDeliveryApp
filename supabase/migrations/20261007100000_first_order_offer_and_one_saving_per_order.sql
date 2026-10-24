-- The first-order welcome offer, and one-saving-per-order for every discount.
--
-- ─── What was wrong ──────────────────────────────────────────────────────────
--
-- `validate_first_order_discount` existed and computed the right number, but:
--
--   1. Nothing ever called it. There was no code path from the cart to it, so it
--      could not affect an order even in principle.
--   2. It was read-only. It returned a figure and never wrote
--      `orders.discount_amount`, and no trigger wrote it either — the six
--      triggers on `orders` are the bill serial, the status timestamp, loyalty
--      on status change, two alert triggers, and cancelled-is-final. So even a
--      working caller would have had nowhere to put the result.
--   3. `store_settings` had no rows at all, so `store_settings_for_branch()`
--      returned nothing and the function's first check
--      (`if s.branch_id is null`) refused with "Welcome offer is unavailable."
--      The offer could not fire for any customer, for any cart.
--   4. It took `p_user_id` from the caller and coalesced it over `auth.uid()`,
--      and was granted to `anon`. A caller could ask about anyone.
--
-- This migration adds a read function that trusts nobody but `auth.uid()`, adds
-- the write function that actually puts the discount on the order, and gives all
-- three discount functions a shared "one saving per order" guard.
--
-- ─── What it deliberately does not do ───────────────────────────────────────
--
-- There is no BEFORE INSERT trigger on `orders`. The offer stands aside the
-- moment the customer picks a voucher or spends points, and only the client
-- knows which of those the customer meant. A trigger would have to guess, and
-- guessing here means either silently overriding a voucher the customer just
-- redeemed or silently stacking two savings. `apply_first_order_discount` is
-- therefore called explicitly at order placement, exactly like the voucher and
-- points functions it sits beside, and it re-derives every condition from the
-- rows that were actually inserted.
--
-- ─── Ordering ────────────────────────────────────────────────────────────────
--
-- Requires 20261007090000_orders_discount_source.sql (the
-- `orders.discount_amount_source` column these functions read and write).

-- ─── 1. Reading the offer ────────────────────────────────────────────────────
--
-- Same job as the old `validate_first_order_discount`, with two differences that
-- matter: the customer is `auth.uid()` and cannot be supplied, and it takes the
-- branch that will fulfil the order rather than guessing from order history.
-- `validate_first_order_discount` is left in place — it is read-only and nothing
-- calls it — so dropping it is a separate decision, not a side effect here.

create or replace function public.first_order_offer(
  p_subtotal  numeric default null,
  p_branch_id uuid    default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  s        public.store_settings%rowtype;
  v_user   uuid := auth.uid();
  v_branch uuid;
  v_orders integer := 0;
  v_amount numeric;
begin
  -- The branch decides the terms: each branch sets its own percentage, cap and
  -- minimum. Falling back to the customer's last order is what the loyalty
  -- screen does, and it is the wrong default here — a brand new customer has no
  -- order history, which is precisely the customer this is for.
  v_branch := coalesce(p_branch_id, public.customer_branch_id(v_user));

  select * into s from public.store_settings_for_branch(v_branch);

  if s.branch_id is null then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'message', 'Welcome offer is unavailable.');
  end if;

  if not s.first_order_discount_enabled then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'message', 'Welcome offer is not active right now.');
  end if;

  if v_user is null then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'message', 'Sign in to receive the welcome offer.');
  end if;

  -- "First order" means exactly this: no rows, at all, for this customer. Not
  -- "no delivered orders" and not "no orders at this branch" — a customer whose
  -- only order was cancelled has still ordered before, and a cancelled order
  -- does not earn points either, so the two rules agree.
  select count(*) into v_orders from public.orders where customer_id = v_user;

  if v_orders > 0 then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'message', 'Welcome offer is for first-time orders only.');
  end if;

  if coalesce(s.first_order_min_subtotal, 0) > coalesce(p_subtotal, 0) then
    return jsonb_build_object(
      'ok', false, 'discount_amount', 0,
      'min_order_amount', coalesce(s.first_order_min_subtotal, 0),
      'message', 'Welcome offer needs a minimum subtotal of Rs. '
        || round(coalesce(s.first_order_min_subtotal, 0)) || '.');
  end if;

  v_amount := round(coalesce(p_subtotal, 0) * s.first_order_discount_pct / 100);
  v_amount := least(v_amount, coalesce(s.first_order_max_cap, v_amount));
  v_amount := least(greatest(coalesce(v_amount, 0), 0), coalesce(p_subtotal, 0));

  if v_amount <= 0 then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'message', 'Welcome offer gives no discount on this order.');
  end if;

  return jsonb_build_object(
    'ok', true,
    'discount_amount', v_amount,
    'discount_percentage', s.first_order_discount_pct,
    'min_order_amount', coalesce(s.first_order_min_subtotal, 0),
    'max_discount_amount', s.first_order_max_cap,
    'message', 'Welcome offer — ' || s.first_order_discount_pct
      || '% off your first order (Rs. ' || v_amount || ' saved).');
end;
$$;

grant execute on function public.first_order_offer(numeric, uuid)
  to anon, authenticated;

-- ─── 2. Putting it on the order ─────────────────────────────────────────────

create or replace function public.apply_first_order_discount(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_order   public.orders%rowtype;
  s         public.store_settings%rowtype;
  v_user    uuid := auth.uid();
  v_orders  integer := 0;
  v_amount  numeric;
  v_base    numeric;
  v_new     numeric;
begin
  if v_user is null then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'message', 'Sign in to receive the welcome offer.');
  end if;

  if p_order_id is null then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'message', 'An order id is required.');
  end if;

  -- Locked, so a second call cannot slip in between this check and the write.
  select * into v_order
    from public.orders
   where id = p_order_id
     for update;

  if not found then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'message', 'Order not found.');
  end if;

  if v_order.customer_id is distinct from v_user then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'message', 'That is not your order.');
  end if;

  -- One saving per order. A voucher or a points spend on this order means the
  -- customer chose that one, and it stands.
  if v_order.discount_amount_source in ('voucher', 'loyalty_points') then
    return jsonb_build_object(
      'ok', false, 'discount_amount', 0,
      'message', case v_order.discount_amount_source
        when 'voucher' then 'A voucher is already applied to this order.'
        else 'You are already using your points on this order.'
      end);
  end if;

  if v_order.discount_amount_source = 'first_order' then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'message', 'The welcome offer is already applied to this order.');
  end if;

  select * into s from public.store_settings_for_branch(v_order.branch_id);

  if s.branch_id is null then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'message', 'Welcome offer is unavailable.');
  end if;

  if not s.first_order_discount_enabled then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'message', 'Welcome offer is not active right now.');
  end if;

  -- Counted against the order being discounted, so an offer cannot be spent on
  -- an order that is itself the first one twice over.
  select count(*) into v_orders
    from public.orders
   where customer_id = v_user
     and id <> p_order_id;

  if v_orders > 0 then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'message', 'Welcome offer is for first-time orders only.');
  end if;

  if coalesce(s.first_order_min_subtotal, 0) > coalesce(v_order.subtotal, 0) then
    return jsonb_build_object(
      'ok', false, 'discount_amount', 0,
      'min_order_amount', coalesce(s.first_order_min_subtotal, 0),
      'message', 'Welcome offer needs a minimum subtotal of Rs. '
        || round(coalesce(s.first_order_min_subtotal, 0)) || '.');
  end if;

  -- From the order rows, not from anything the client sent. The subtotal is the
  -- order's own column, so a modified client asking for a bigger discount, or
  -- for an order that is not their first, is refused rather than believed.
  v_amount := round(coalesce(v_order.subtotal, 0) * s.first_order_discount_pct / 100);
  v_amount := least(v_amount, coalesce(s.first_order_max_cap, v_amount));
  v_amount := least(greatest(coalesce(v_amount, 0), 0), coalesce(v_order.subtotal, 0));

  if v_amount <= 0 then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'message', 'Welcome offer gives no discount on this order.');
  end if;

  v_base := v_order.subtotal + v_order.tax + v_order.delivery_charges;
  v_new := greatest(v_base - v_amount, 0);

  update public.orders
     set discount_amount = v_amount,
         discount_amount_source = 'first_order',
         total = v_new
   where id = p_order_id;

  return jsonb_build_object(
    'ok', true,
    'discount_amount', round(v_amount, 2),
    'discount_percentage', s.first_order_discount_pct,
    'min_order_amount', coalesce(s.first_order_min_subtotal, 0),
    'max_discount_amount', s.first_order_max_cap,
    'new_total', round(v_new, 2),
    'message', 'Welcome offer applied — ' || s.first_order_discount_pct
      || '% off your first order (Rs. ' || v_amount || ' saved).');
end;
$$;

grant execute on function public.apply_first_order_discount(uuid)
  to authenticated;

-- ─── 3. Vouchers: honour the branch they are restricted to ──────────────────
--
-- `vouchers.branch_id` has existed all along — NULL for both branches, a branch
-- id for one — and both `validate_voucher` and `redeem_voucher` ignored it
-- completely. A voucher a manager had restricted to Abbottabad validated and
-- redeemed against a Mansehra order. Two fixes: read the column, and have
-- `redeem_voucher` pass the *order's* branch down rather than relying on the
-- customer to have ordered from that branch before.

-- Signature is unchanged, so this replaces the body rather than dropping the
-- function — no window in which a customer's voucher check finds it missing.
create or replace function public.validate_voucher(
  p_code           text,
  p_subtotal       numeric,
  p_user_id        uuid,
  p_menu_item_ids  uuid[],
  p_branch_id      uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v         public.vouchers%rowtype;
  v_base    jsonb;
  v_amount  numeric;
  v_fee     numeric;
  v_user    uuid := coalesce(p_user_id, auth.uid());
  v_branch  uuid;
  v_uses    integer := 0;
  v_total   integer := 0;
  v_scoped  boolean := false;
  v_allowed uuid[];
begin
  select * into v
    from public.vouchers
   where upper(btrim(code)) = upper(btrim(coalesce(p_code, '')))
   limit 1;

  if v.id is null then
    return jsonb_build_object('ok', false,
      'code', upper(btrim(coalesce(p_code, ''))),
      'message', 'Invalid voucher code.');
  end if;

  v_base := jsonb_build_object(
    'code', v.code,
    'voucher_id', v.id,
    'discount_type', v.discount_type,
    'discount_value', v.discount_value,
    'min_order_amount', coalesce(v.min_order_amount, 0),
    'max_discount_amount', v.max_discount_amount,
    'valid_to', v.valid_to);

  if not v.is_active then
    return v_base || jsonb_build_object('ok', false,
      'message', 'This voucher is no longer active.');
  end if;

  if v.valid_from > now() then
    return v_base || jsonb_build_object('ok', false,
      'message', 'This voucher is not valid yet.');
  end if;

  if v.valid_to < now() then
    return v_base || jsonb_build_object('ok', false,
      'message', 'This voucher expired on ' || to_char(v.valid_to, 'Mon DD, YYYY') || '.');
  end if;

  -- A voucher with a branch is for that branch only. A voucher without one is
  -- for both. When the voucher is restricted and the order's branch cannot be
  -- established, the code is refused rather than assumed good: the app always
  -- passes the branch, so this only guards a direct call.
  if v.branch_id is not null then
    v_branch := coalesce(p_branch_id, public.customer_branch_id(v_user));

    if v_branch is null or v.branch_id is distinct from v_branch then
      return v_base || jsonb_build_object('ok', false,
        'message', 'This voucher is not valid at the branch you selected.');
    end if;
  end if;

  select exists (select 1 from public.voucher_menu_items where voucher_id = v.id)
    into v_scoped;

  if v_scoped then
    if p_menu_item_ids is null or coalesce(array_length(p_menu_item_ids, 1), 0) = 0 then
      return v_base || jsonb_build_object('ok', false, 'scoped', true,
        'message', 'This voucher only applies to selected menu items.');
    end if;

    select array_agg(menu_item_id) into v_allowed
      from public.voucher_menu_items
     where voucher_id = v.id
       and menu_item_id = any (p_menu_item_ids);

    if v_allowed is null
       or coalesce(array_length(v_allowed, 1), 0) <> coalesce(array_length(p_menu_item_ids, 1), 0) then
      return v_base || jsonb_build_object('ok', false, 'scoped', true,
        'message', 'This voucher only applies to selected menu items - remove the other items from your cart to use it.');
    end if;
  end if;

  if coalesce(v.min_order_amount, 0) > coalesce(p_subtotal, 0) then
    return v_base || jsonb_build_object('ok', false,
      'message', 'This voucher needs a minimum subtotal of Rs. ' || round(coalesce(v.min_order_amount, 0)) || '.');
  end if;

  if v_user is not null and coalesce(v.usage_limit_per_user, 1) > 0 then
    select count(*) into v_uses from public.voucher_redemptions
     where voucher_id = v.id and user_id = v_user;
    if v_uses >= coalesce(v.usage_limit_per_user, 1) then
      return v_base || jsonb_build_object('ok', false,
        'message', 'You have already used this voucher.');
    end if;
  end if;

  if coalesce(v.total_usage_limit, 0) > 0 then
    select count(*) into v_total from public.voucher_redemptions where voucher_id = v.id;
    if v_total >= v.total_usage_limit then
      return v_base || jsonb_build_object('ok', false,
        'message', 'This voucher has been fully claimed.');
    end if;
  end if;

  -- Free delivery reads the fee from the BRANCH that will fulfil the order.
  -- With one global row this was unambiguous. With a row per branch it is not,
  -- so p_branch_id is what makes "free delivery" mean a real figure. The comment
  -- that this "never reads from the app" still holds: the app names the branch,
  -- not the amount.
  if v.discount_type = 'free_delivery' then
    select coalesce(s.delivery_fee, 0) into v_fee
      from public.store_settings_for_branch(
        coalesce(p_branch_id, public.customer_branch_id(v_user))) s;

    v_fee := coalesce(v_fee, 0);

    if v_fee <= 0 then
      return v_base || jsonb_build_object('ok', false, 'scoped', v_scoped, 'free_delivery', false,
        'message', 'Delivery is already free on this order.');
    end if;

    return v_base || jsonb_build_object(
      'ok', true, 'scoped', v_scoped, 'free_delivery', true,
      'delivery_fee', v_fee, 'discount_amount', v_fee,
      'message', 'Voucher applied - free delivery (Rs. ' || v_fee || ' saved).');
  end if;

  if v.discount_type = 'percentage' then
    v_amount := round(coalesce(p_subtotal, 0) * v.discount_value / 100);
  else
    v_amount := v.discount_value;
  end if;

  if coalesce(v.max_discount_amount, 0) > 0 then
    v_amount := least(v_amount, v.max_discount_amount);
  end if;

  v_amount := least(greatest(coalesce(v_amount, 0), 0), coalesce(p_subtotal, 0));

  if v_amount <= 0 then
    return v_base || jsonb_build_object('ok', false, 'scoped', v_scoped,
      'message', 'This voucher gives no discount on this order.');
  end if;

  return v_base || jsonb_build_object(
    'ok', true, 'scoped', v_scoped, 'free_delivery', false,
    'discount_amount', v_amount,
    'message', case
      when v.discount_type = 'percentage'
        then 'Voucher applied - ' || trim(trailing '.' from trim(trailing '0' from v.discount_value::text)) || '% off (Rs. ' || v_amount || ' saved).'
      else 'Voucher applied - Rs. ' || v_amount || ' off.'
    end);
end;
$$;

grant execute on function public.validate_voucher(text, numeric, uuid, uuid[], uuid)
  to anon, authenticated;

-- ─── 4. redeem_voucher: the order's branch, and record what it spent ─────────

create or replace function public.redeem_voucher(p_code text, p_order_id uuid, p_user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_user     uuid := coalesce(p_user_id, auth.uid());
  v_order    public.orders%rowtype;
  v_subtotal numeric;
  v_items    uuid[];
  v_check    jsonb;
  v_amount   numeric;
begin
  if p_order_id is null then
    return jsonb_build_object('ok', false, 'message', 'An order id is required to redeem a voucher.');
  end if;

  if v_user is null then
    return jsonb_build_object('ok', false, 'message', 'Sign in to redeem a voucher.');
  end if;

  select * into v_order
    from public.orders
   where id = p_order_id
     for update;

  if not found then
    return jsonb_build_object('ok', false, 'message', 'Order not found.');
  end if;

  if v_order.customer_id is distinct from v_user then
    return jsonb_build_object('ok', false, 'message', 'That is not your order.');
  end if;

  -- One saving per order. Without this, a voucher set `discount_amount` outright
  -- and silently erased a points saving that was already on the order while the
  -- loyalty ledger kept the debit — the customer lost the points and got nothing
  -- back for them.
  if v_order.discount_amount_source is not null then
    return jsonb_build_object(
      'ok', false,
      'message', case v_order.discount_amount_source
        when 'loyalty_points' then 'You are already using your points on this order.'
        when 'first_order' then 'The welcome offer is already applied to this order.'
        else 'This voucher has already been applied to this order.'
      end);
  end if;

  -- The discount is computed from what was actually ordered, not from whatever
  -- the cart said at checkout.
  select coalesce(sum(oi.quantity * oi.price_at_order), 0)
    into v_subtotal
    from public.order_items oi
   where oi.order_id = p_order_id;

  if v_subtotal is null or v_subtotal <= 0 then
    v_subtotal := v_order.subtotal;
  end if;

  if v_subtotal is null or v_subtotal <= 0 then
    return jsonb_build_object('ok', false, 'message', 'Order not found.');
  end if;

  select coalesce(array_agg(distinct oi.menu_item_id), '{}') into v_items
    from public.order_items oi
   where oi.order_id = p_order_id;

  -- The ORDER's branch, so a voucher restricted to one branch is checked
  -- against the branch actually fulfilling the order. This used to fall back to
  -- the customer's most recent order, which for a first-time customer is no
  -- branch at all — which is how a branch-restricted voucher came to validate
  -- against a branch nobody had checked.
  v_check := public.validate_voucher(p_code, v_subtotal, v_user, v_items, v_order.branch_id);
  if not coalesce((v_check ->> 'ok')::boolean, false) then
    return v_check;
  end if;

  v_amount := (v_check ->> 'discount_amount')::numeric;

  insert into public.voucher_redemptions (voucher_id, user_id, order_id)
  values ((v_check ->> 'voucher_id')::uuid, v_user, p_order_id)
  on conflict (voucher_id, order_id) do nothing;

  -- FIX: total was left at the pre-discount figure, so an order row could carry
  -- a real discount_amount alongside a total that still included it. Every
  -- SET expression below sees the OLD row, so the fee is resolved first and the
  -- total is rebuilt from it.
  update public.orders
     set discount_amount = v_amount,
         discount_amount_source = 'voucher',
         delivery_charges = case
           when coalesce((v_check ->> 'free_delivery')::boolean, false) then 0
           else delivery_charges
         end,
         total = greatest(
           subtotal
           + tax
           + (case
                when coalesce((v_check ->> 'free_delivery')::boolean, false) then 0
                else delivery_charges
              end)
           - v_amount,
           0)
   where id = p_order_id;

  return v_check || jsonb_build_object('ok', true, 'order_id', p_order_id, 'recorded', true);
end;
$$;

-- ─── 5. redeem_loyalty_points: the same one-saving rule ──────────────────────
--
-- Unchanged except for the guard above the balance check and the
-- `discount_amount_source` write, so the ledger, the clamping and the refusal
-- wording all behave exactly as they did.

create or replace function public.redeem_loyalty_points(p_order_id uuid, p_points integer)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_order     public.orders%rowtype;
  v_settings  public.store_settings%rowtype;
  v_balance   integer := 0;
  v_value     numeric;
  v_discount  numeric := 0;
  v_remaining numeric;
  v_base      numeric;
  v_spendable integer;
  v_spent     integer;
  v_new_total numeric := 0;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok', false, 'message', 'Sign in to spend your loyalty points.');
  end if;

  if p_order_id is null then
    return jsonb_build_object('ok', false, 'message', 'An order id is required.');
  end if;

  if p_points is null or p_points <= 0 then
    return jsonb_build_object('ok', false, 'message', 'Enter how many points to spend.');
  end if;

  select * into v_order
    from public.orders
   where id = p_order_id
     for update;

  if not found then
    return jsonb_build_object('ok', false, 'message', 'Order not found.');
  end if;

  if v_order.customer_id is distinct from auth.uid() then
    return jsonb_build_object('ok', false, 'message', 'That is not your order.');
  end if;

  if v_order.status = 'delivered' or v_order.status = 'cancelled' then
    return jsonb_build_object(
      'ok', false,
      'message', 'Points can only be spent before an order is delivered.'
    );
  end if;

  -- One saving per order, decided here rather than by the order the client's
  -- requests happened to arrive in.
  if v_order.discount_amount_source is not null then
    return jsonb_build_object(
      'ok', false,
      'message', case v_order.discount_amount_source
        when 'voucher' then 'A voucher is already applied to this order.'
        when 'first_order' then 'The welcome offer is already applied to this order.'
        else 'You have already used points on this order.'
      end);
  end if;

  select * into v_settings
    from public.store_settings_for_branch(v_order.branch_id);
  if v_settings.branch_id is null
     or not v_settings.loyalty_enabled
     or coalesce(v_settings.loyalty_redemption_value, 0) <= 0 then
    return jsonb_build_object(
      'ok', false,
      'message', 'Loyalty points cannot be spent right now.'
    );
  end if;

  select coalesce(sum(points), 0)::integer into v_balance
    from public.loyalty_ledger
   where user_id = auth.uid();

  if p_points > v_balance then
    return jsonb_build_object(
      'ok', false,
      'message', 'You have ' || v_balance || ' points available.'
    );
  end if;

  if exists (
    select 1 from public.loyalty_ledger
     where order_id = p_order_id and entry_type = 'redeemed'
  ) then
    return jsonb_build_object(
      'ok', false,
      'message', 'You have already used points on this order.'
    );
  end if;

  v_value := v_settings.loyalty_redemption_value;

  v_remaining := greatest(v_order.subtotal - coalesce(v_order.discount_amount, 0), 0);

  if v_remaining <= 0 then
    return jsonb_build_object(
      'ok', false,
      'message', 'This order is already fully discounted.'
    );
  end if;

  -- Clamp to what the order can absorb, then round DOWN to whole points.
  v_discount := least(p_points * v_value, v_remaining);
  v_spendable := floor(v_discount / v_value);

  if v_spendable <= 0 then
    return jsonb_build_object(
      'ok', false,
      'message', 'You do not have enough points to cover any part of this order.'
    );
  end if;

  v_spent := v_spendable;
  v_discount := v_spent * v_value;

  v_base := v_order.subtotal + v_order.tax + v_order.delivery_charges;
  v_new_total := greatest(
    v_base - coalesce(v_order.discount_amount, 0) - v_discount, 0);

  insert into public.loyalty_ledger (user_id, order_id, points, entry_type, reason)
  values (
    auth.uid(),
    p_order_id,
    -v_spent,
    'redeemed',
    'Points spent on order ' || coalesce(v_order.bill_serial_number, left(v_order.id::text, 8))
  );

  update public.orders
     set discount_amount = coalesce(discount_amount, 0) + v_discount,
         discount_amount_source = 'loyalty_points',
         total = v_new_total
   where id = p_order_id;

  return jsonb_build_object(
    'ok', true,
    'points_spent', v_spent,
    'discount_applied', round(v_discount, 2),
    'new_total', round(v_new_total, 2),
    'balance', v_balance - v_spent,
    'message', 'Spent ' || v_spent || ' points and saved Rs. ' || round(v_discount, 2) || '.'
  );
end;
$$;