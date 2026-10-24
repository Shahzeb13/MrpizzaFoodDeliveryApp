-- ═══════════════════════════════════════════════════════════════════════════
-- store_settings becomes per-branch
--
-- One global row with CHECK (id = 1) becomes one row per branch, keyed by
-- branch_id. Delivery fee, store hours, the welcome offer and every loyalty
-- rate are each branch's own decision: the Abbottabad manager and the Mansehra
-- manager set their numbers independently, and neither can see or change the
-- other's.
--
-- Nothing is seeded. Each branch manager creates their own row from the admin
-- panel, so this migration deliberately leaves the table empty.
--
-- Why the loyalty columns move too: a customer is not tied to a branch, so a
-- per-branch loyalty rate cannot be resolved from the customer alone. It is
-- resolved from the branch of the order being placed, which is exact for
-- earning and for spending, and from the customer's most recent order for the
-- points screen.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 1. Reshape the table ────────────────────────────────────────────────

alter table public.store_settings
  drop constraint if exists store_settings_single_row;

alter table public.store_settings
  add column if not exists branch_id uuid references public.branches(id);

-- The one global row cannot become a branch row: it belongs to no branch.
-- Dropping it is the point of this migration. Every branch manager sets their
-- own values in the panel.
delete from public.store_settings where branch_id is null;

alter table public.store_settings
  drop constraint if exists store_settings_pkey;

alter table public.store_settings
  drop column if exists id;

alter table public.store_settings
  add primary key (branch_id);

comment on table public.store_settings is
  'Per-branch store settings. One row per branch, created by that branch''s '
  'manager. Values that differ per branch by deliberate decision: delivery fee, '
  'store hours, welcome offer, loyalty rates.';

-- ─── 2. Branch helpers ───────────────────────────────────────────────────

-- The single question the six functions below all needed answered: which row?
create or replace function public.store_settings_for_branch(p_branch_id uuid)
returns public.store_settings
language sql
stable
set search_path = 'public'
as $$
  select * from public.store_settings where branch_id = p_branch_id
$$;

-- A customer has no branch of their own. For the points screen, which has no
-- order to read, fall back to the branch of their most recent order. Null for
-- a customer who has never ordered, which the caller must handle rather than
-- silently substituting some other branch's numbers.
create or replace function public.customer_branch_id(p_customer uuid)
returns uuid
language sql
stable
set search_path = 'public'
as $$
  select o.branch_id
    from public.orders o
   where o.customer_id = p_customer
   order by o.created_at desc nulls last
   limit 1
$$;

-- The caller's own branch, for panel-side reads. Added here because
-- admin_loyalty_overview needs it; no existing policy is rewired by this
-- migration.
create or replace function public.my_branch_id()
returns uuid
language sql
stable
security definer
set search_path = 'public'
as $$
  select branch_id from public.admin_users where id = (select auth.uid()) limit 1
$$;

comment on function public.customer_branch_id(uuid) is
  'The branch to read a customer''s per-branch settings from. Derived from the '
  'most recent order because customers are not assigned to a branch. Null when '
  'the customer has never ordered.';

-- ─── 3. Earning and spending: the order already carries its branch ───────
-- These two are the unambiguous ones. No guessing, no fallback.

create or replace function public.award_points_for_order(p_order_id uuid)
returns integer
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_order    public.orders%rowtype;
  v_settings public.store_settings%rowtype;
  v_points   integer;
  v_serial   text;
  v_awarded  integer := 0;
begin
  select * into v_order from public.orders where id = p_order_id;
  if not found then
    return 0;
  end if;

  if v_order.status is distinct from 'delivered' then
    return 0;
  end if;

  select * into v_settings
    from public.store_settings_for_branch(v_order.branch_id);
  -- The helper always returns one row, so `found` is true even when it is a
  -- null row. Test the branch, not `found`.
  if v_settings.branch_id is null then
    return 0;
  end if;

  if not v_settings.loyalty_enabled then
    return 0;
  end if;

  if v_settings.loyalty_rupees_per_point is null
     or v_settings.loyalty_rupees_per_point <= 0 then
    return 0;
  end if;

  -- Floor, so a Rs. 1,999 order at "Rs 100 = 1 point" pays 19, not 20.
  v_points := floor(v_order.total / v_settings.loyalty_rupees_per_point)::integer;

  if coalesce(v_settings.loyalty_min_order_total, 0) > 0
     and v_order.total < v_settings.loyalty_min_order_total then
    return 0;
  end if;

  if v_settings.loyalty_max_points_per_order > 0
     and v_points > v_settings.loyalty_max_points_per_order then
    v_points := v_settings.loyalty_max_points_per_order;
  end if;

  if v_points <= 0 then
    return 0;
  end if;

  v_serial := coalesce(v_order.bill_serial_number, left(v_order.id::text, 8));

  insert into public.loyalty_ledger (user_id, order_id, points, entry_type, reason)
  values (
    v_order.customer_id,
    p_order_id,
    v_points,
    'earned',
    'Order ' || v_serial || ' delivered'
  )
  on conflict (user_id, order_id) where entry_type = 'earned' and order_id is not null
  do nothing;

  -- Return what was ACTUALLY inserted. If this order already paid out the
  -- conflict swallowed the insert, and the caller must see 0 rather than a
  -- phantom award.
  get diagnostics v_awarded = row_count;
  return coalesce(v_awarded * v_points, 0);
end;
$$;

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

-- ─── 4. Points screen: no order, so the last order's branch ──────────────

create or replace function public.get_my_loyalty_balance()
returns jsonb
language plpgsql
stable
security definer
set search_path = 'public'
as $$
declare
  v_user     uuid := auth.uid();
  v_balance  integer := 0;
  v_history  jsonb;
  v_settings jsonb;
begin
  if v_user is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'Sign in to see your loyalty points.'
    );
  end if;

  select coalesce(sum(points), 0)::integer into v_balance
    from public.loyalty_ledger
   where user_id = v_user;

  select coalesce(jsonb_agg(row_to_json(h) order by h.created_at desc), '[]'::jsonb)
    into v_history
    from (
      select points, entry_type, reason, created_at, order_id
        from public.loyalty_ledger
       where user_id = v_user
       order by created_at desc
       limit 50
    ) h;

  -- Separate variable: reusing v_history here would overwrite the list
  -- of transactions built above.
  --
  -- Stays '{}' for a customer who has never ordered, so the app shows a balance
  -- with no rates attached rather than another branch's rates.
  select coalesce(
    (select jsonb_build_object(
      'enabled',          s.loyalty_enabled,
      'rupees_per_point', s.loyalty_rupees_per_point,
      'redemption_value', s.loyalty_redemption_value
    ) from public.store_settings_for_branch(public.customer_branch_id(v_user)) s
      where s.branch_id is not null),
    '{}'::jsonb
  ) into v_settings;

  return jsonb_build_object(
    'ok', true,
    'balance',  v_balance,
    'history',  v_history,
    'settings', v_settings
  );
end;
$$;

-- ─── 5. Checkout validators: the fulfilling branch, passed in ─────────────
--
-- p_branch_id is the branch that will fulfil the order. It is NOT optional in
-- practice: the app already resolves the fulfilling branch at checkout, so it
-- has the id. It defaults to null so existing callers keep compiling, and a
-- null falls back to the customer's most recent order.

-- Drop first. CREATE OR REPLACE with a new parameter creates an *overload*,
-- not a replacement, and two same-named functions would make every call
-- ambiguous. Grants are recreated below.
drop function if exists public.validate_first_order_discount(uuid, numeric);

create function public.validate_first_order_discount(
  p_user_id    uuid default null,
  p_subtotal   numeric default null,
  p_branch_id  uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  s        public.store_settings%rowtype;
  v_orders integer;
  v_amount numeric;
  v_user   uuid := coalesce(p_user_id, auth.uid());
begin
  select * into s
    from public.store_settings_for_branch(
      coalesce(p_branch_id, public.customer_branch_id(v_user)));

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

  select count(*) into v_orders from public.orders where customer_id = v_user;
  if v_orders > 0 then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'message', 'Welcome offer is for first-time orders only.');
  end if;

  if coalesce(s.first_order_min_subtotal, 0) > coalesce(p_subtotal, 0) then
    return jsonb_build_object('ok', false, 'discount_amount', 0,
      'min_order_amount', coalesce(s.first_order_min_subtotal, 0),
      'message', 'Welcome offer needs a minimum subtotal of Rs. ' || round(coalesce(s.first_order_min_subtotal, 0)) || '.');
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

grant execute on function public.validate_first_order_discount(uuid, numeric, uuid)
  to anon, authenticated;

drop function if exists public.validate_voucher(text, numeric, uuid, uuid[]);

create function public.validate_voucher(
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

-- ─── 6. Panel: the manager's own branch ──────────────────────────────────

create or replace function public.admin_loyalty_overview()
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_settings jsonb;
  v_members  jsonb;
  v_recent   jsonb;
  v_stats    jsonb;
begin
  -- Was "where s.id = 1", which handed every manager the same numbers. Now it
  -- is the caller's own branch, and a manager with no admin_users row gets null
  -- rather than another branch's settings.
  select to_jsonb(s) - 'branch_id' into v_settings
    from public.store_settings_for_branch(public.my_branch_id()) s;

  -- Every customer profile, whether or not they hold any points yet, so
  -- the table does not shrink to just the people who have ordered.
  select coalesce(
           jsonb_agg(to_jsonb(m) order by m.balance desc nulls last, m.full_name),
           '[]'::jsonb)
    into v_members
    from (
      select p.id,
             p.full_name,
             p.phone,
             p.created_at,
             coalesce(b.balance, 0)      as balance,
             coalesce(b.entries, 0)      as entries,
             b.last_activity,
             coalesce(o.orders_count, 0) as orders_count,
             coalesce(o.total_spent, 0)  as total_spent
        from public.profiles p
        left join public.loyalty_balances b on b.user_id = p.id
        left join lateral (
          select count(*) as orders_count,
                 coalesce(sum(total), 0) as total_spent
            from public.orders ord
           where ord.customer_id = p.id
             and ord.status = 'delivered'
        ) o on true
       where p.role = 'customer'
    ) m;

  select coalesce(jsonb_agg(row_to_json(r)), '[]'::jsonb)
    into v_recent
    from (
      select l.id,
             l.user_id,
             l.points,
             l.entry_type,
             l.reason,
             l.created_at,
             l.order_id,
             o.bill_serial_number,
             o.total as order_total,
             p.full_name,
             p.phone
        from public.loyalty_ledger l
        left join public.profiles p on p.id = l.user_id
        left join public.orders  o on o.id = l.order_id
       order by l.created_at desc
       limit 50
    ) r;

  select jsonb_build_object(
           'total_outstanding',   coalesce((select sum(points) from public.loyalty_ledger), 0),
           'points_earned',       coalesce((select sum(points) from public.loyalty_ledger where points > 0), 0),
           'points_reversed',     coalesce((select -sum(points) from public.loyalty_ledger where points < 0), 0),
           'earned_this_month',   coalesce((select sum(points) from public.loyalty_ledger
                                              where points > 0
                                                and created_at >= date_trunc('month', now())), 0),
           'customers',           (select count(*) from public.profiles where role = 'customer'),
           'members_with_points', (select count(*) from public.loyalty_balances),
           'transactions',        (select count(*) from public.loyalty_ledger)
         )
    into v_stats;

  return jsonb_build_object(
           'ok',       true,
           'settings', v_settings,
           'members',  v_members,
           'recent',   v_recent,
           'stats',    v_stats
         );
end;
$$;

-- ─── 7. The demo script reads the rate for its log line ──────────────────
-- Only the human-readable log line changes. Its expected values are hardcoded
-- to Rs 20 per point, so it now reads the rate of the branch it picked and
-- will report a FAIL if the two branches ever diverge on loyalty.

create or replace function public.loyalty_demo_simulation(p_keep_data boolean)
returns table (step text, what_happened text)
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_cust    uuid;
  v_branch  uuid;
  v_menu    uuid;
  v_order1  uuid;
  v_order2  uuid;
  v_result  jsonb;
  v_before  integer;
  v_balance integer;
  v_base    integer;
  v_delta   integer;
begin
  step := null;
  what_happened := null;

  create temporary table if not exists demo_log (step text, what_happened text)
    on commit drop;
  delete from demo_log;

  select id into v_cust from public.profiles where role = 'customer'
   order by created_at limit 1;
  select id into v_branch from public.branches where is_active limit 1;
  select id into v_menu from public.menu_items where is_available limit 1;

  if v_cust is null then
    insert into demo_log values ('STOP', 'No customer profile found.');
    return query select l.step, l.what_happened from demo_log l;
    return;
  end if;

  perform set_config('request.jwt.claims',
    '{"role":"authenticated","sub":"' || v_cust || '"}', false);

  select coalesce(sum(points), 0)::integer into v_base
    from public.loyalty_ledger where user_id = v_cust;

  insert into demo_log values ('0. Setup',
    'Acting as: ' || coalesce((select full_name from public.profiles where id = v_cust), 'customer')
    || ' | starting balance: ' || v_base || ' | rate: Rs'
    || (select loyalty_rupees_per_point
          from public.store_settings_for_branch(v_branch))
    || ' = 1 point');

  -- 1. Order placed. Nothing should be earned yet.
  insert into public.orders
    (customer_id, branch_id, order_type, status,
     subtotal, tax, delivery_charges, discount_amount, total, customer_name)
  values (v_cust, v_branch, 'pickup', 'confirmed', 2000, 0, 150, 0, 2150, 'DEMO - earn test')
  returning id into v_order1;
  insert into public.order_items (order_id, menu_item_id, quantity, price_at_order)
  values (v_order1, v_menu, 1, 2000);

  select coalesce(sum(points), 0)::integer into v_balance
    from public.loyalty_ledger where user_id = v_cust;
  v_delta := v_balance - v_base;

  insert into demo_log values ('1. Order placed, total 2,150',
    case when v_delta = 0
      then 'PASS - balance unchanged at ' || v_balance || ', an undelivered order earns nothing'
      else 'FAIL - balance moved by ' || v_delta || ' before delivery' end);

  -- 2. Delivered. Expect +215.
  update public.orders set status = 'delivered' where id = v_order1;
  select coalesce(sum(points), 0)::integer into v_balance
    from public.loyalty_ledger where user_id = v_cust;
  v_delta := v_balance - v_base;

  insert into demo_log values ('2. Marked DELIVERED',
    case when v_delta = 215
      then 'PASS - balance ' || v_base || ' -> ' || v_balance || ' (+215). Trigger awarded floor(2150/10)'
      else 'FAIL - expected +215, got ' || v_delta || ' (balance ' || v_balance || ')' end);

  -- 3. Spend 200 points on a second order.
  insert into public.orders
    (customer_id, branch_id, order_type, status,
     subtotal, tax, delivery_charges, discount_amount, total, customer_name)
  values (v_cust, v_branch, 'pickup', 'confirmed', 1000, 0, 150, 0, 1150, 'DEMO - spend test')
  returning id into v_order2;
  insert into public.order_items (order_id, menu_item_id, quantity, price_at_order)
  values (v_order2, v_menu, 1, 1000);

  v_result := public.redeem_loyalty_points(v_order2, 200);
  select coalesce(sum(points), 0)::integer into v_balance
    from public.loyalty_ledger where user_id = v_cust;
  v_delta := v_balance - (v_base + 215);

  insert into demo_log values ('3. Spent 200 points on order 2',
    case when not coalesce((v_result ->> 'ok')::boolean, false)
      then 'FAIL - ' || coalesce(v_result ->> 'message', 'unknown error')
      when v_delta <> -200
        then 'FAIL - balance moved by ' || v_delta || ', expected -200'
      when (v_result ->> 'new_total')::numeric <> 950
        then 'FAIL - new_total was ' || (v_result ->> 'new_total') || ', expected 950'
      else 'PASS - discount Rs. ' || (v_result ->> 'discount_applied')
           || ', total 1,150 -> ' || (v_result ->> 'new_total')
           || ', balance ' || v_balance end);

  -- 4. Overdraft must be refused.
  v_result := public.redeem_loyalty_points(v_order2, 999999);
  insert into demo_log values ('4. Tried to spend 999,999 points',
    case when coalesce((v_result ->> 'ok')::boolean, false)
      then 'FAIL - it was allowed'
      else 'PASS - refused: ' || coalesce(v_result ->> 'message', '') end);

  -- 5. Clamping.
  declare
    v_order3 uuid;
    v_r3     jsonb;
  begin
    insert into public.orders
      (customer_id, branch_id, order_type, status,
       subtotal, tax, delivery_charges, discount_amount, total, customer_name)
    values (v_cust, v_branch, 'pickup', 'confirmed', 30, 0, 150, 0, 180, 'DEMO - clamp test')
    returning id into v_order3;
    insert into public.order_items (order_id, menu_item_id, quantity, price_at_order)
    values (v_order3, v_menu, 1, 30);

    v_r3 := public.redeem_loyalty_points(v_order3, 500);

    insert into demo_log values ('5. Offered 500 points on a Rs 30 order',
      case when coalesce((v_r3 ->> 'ok')::boolean, false)
        then case when (v_r3 ->> 'points_spent')::int = 30
             then 'PASS - clamped to 30 points, discount Rs. ' || (v_r3 ->> 'discount_applied')
             else 'FAIL - spent ' || (v_r3 ->> 'points_spent') || ', expected a clamp to 30' end
        else 'NOTE - ' || coalesce(v_r3 ->> 'message', '') end);

    delete from public.loyalty_ledger       where order_id = v_order3;
    delete from public.order_items          where order_id = v_order3;
    delete from public.order_status_history where order_id = v_order3;
    delete from public.order_alerts         where order_id = v_order3;
    delete from public.orders               where id = v_order3;
  end;

  -- 6. Cancel the order that used points, before it was ever delivered.
  --    This is the case that used to be broken: the reversal only fired on
  --    delivered -> cancelled, so the 200 points were never given back.
  select coalesce(sum(points), 0)::integer into v_before
    from public.loyalty_ledger where user_id = v_cust;
  update public.orders set status = 'cancelled' where id = v_order2;
  select coalesce(sum(points), 0)::integer into v_balance
    from public.loyalty_ledger where user_id = v_cust;
  v_delta := v_balance - v_before;

  insert into demo_log values ('6. Cancelled the paid order (never delivered)',
    case when v_delta = 200
      then 'PASS - balance ' || v_before || ' -> ' || v_balance
           || ' (+200). Points refunded on cancellation'
      else 'FAIL - balance ' || v_before || ' -> ' || v_balance
           || ', change was ' || v_delta || ' not +200. Points were NOT refunded' end);

  -- 7. Cancel the delivered order. Earned points must be clawed back.
  select coalesce(sum(points), 0)::integer into v_before
    from public.loyalty_ledger where user_id = v_cust;
  update public.orders set status = 'cancelled' where id = v_order1;
  select coalesce(sum(points), 0)::integer into v_balance
    from public.loyalty_ledger where user_id = v_cust;
  v_delta := v_balance - v_before;

  insert into demo_log values ('7. Cancelled the delivered order',
    case when v_delta = -215
      then 'PASS - balance ' || v_before || ' -> ' || v_balance
           || ' (-215). Earned points reversed'
      else 'FAIL - expected -215, got ' || v_delta end);

  insert into demo_log values ('8. Final balance',
    case when v_balance = v_base
      then 'PASS - ' || v_balance || ' points, exactly where this customer started'
      else 'FAIL - ' || v_balance || ' points, started at ' || v_base
           || '. The customer lost or gained ' || (v_base - v_balance) || ' points' end);

  if p_keep_data then
    insert into demo_log values ('9. Cleanup',
      'KEPT on purpose, so the admin panel has real demo data to show.');
  else
    delete from public.loyalty_ledger       where order_id in (v_order1, v_order2);
    delete from public.order_items          where order_id in (v_order1, v_order2);
    delete from public.order_status_history where order_id in (v_order1, v_order2);
    delete from public.order_alerts         where order_id in (v_order1, v_order2);
    delete from public.orders               where id in (v_order1, v_order2);

    insert into demo_log values ('9. Cleanup', 'Demo orders removed. Your database is exactly as it was.');
  end if;

  return query select l.step, l.what_happened from demo_log l;
end;
$$;

-- ─── 8. A read that scans orders for every points-screen open ────────────
-- customer_branch_id() orders by orders.created_at filtered on customer_id,
-- and there is no index on either. Without this the points screen gets slower
-- the more history a customer has.
create index if not exists orders_customer_id_created_at_idx
  on public.orders (customer_id, created_at desc);
