-- Lock `apply_first_order_discount` down to signed-in customers.
--
-- A newly created function inherits EXECUTE from PUBLIC, so
-- 20261007100000_first_order_offer_and_one_saving_per_order.sql granted it to
-- `authenticated` but did not take it away from `anon` and `PUBLIC`. The
-- function refuses without a session ("Sign in to receive the welcome offer."),
-- so nothing was exploitable — but it should not be reachable by an anonymous
-- caller at all, and `redeem_loyalty_points` was already tightened this way by
-- 20261002211240_loyalty_fix_role_check_and_grants, so the two now agree.
--
-- A permission removal only: no tables, no rows, no orders.

revoke execute on function public.apply_first_order_discount(uuid) from public, anon;
grant  execute on function public.apply_first_order_discount(uuid) to authenticated;