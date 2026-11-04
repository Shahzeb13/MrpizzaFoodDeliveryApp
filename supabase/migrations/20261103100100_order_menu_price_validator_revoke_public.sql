-- Finish the lock-down of the read-only price-floor validator: Postgres
-- grants EXECUTE to PUBLIC when a function is created, which the first
-- migration's per-role revokes did not touch. PUBLIC is a grantee of its own,
-- so it must also be revoked from PUBLIC.
--
-- The trigger keeps working: invoking a trigger function is not gated on the
-- calling user having EXECUTE.
REVOKE EXECUTE ON FUNCTION public.validate_order_menu_pricing() FROM PUBLIC;
