-- Give each branch its store_settings row.
--
-- `store_settings` had no rows at all. Both branches existed, the columns had
-- sensible defaults (first-order 15%, cap 300, minimum subtotal 1000, delivery
-- fee 150, loyalty on at Rs 10 per point with Rs 1 redemption), and nothing had
-- ever written them — the table became per-branch in
-- 20261005210000_store_settings_per_branch.sql, which made `branch_id` NOT NULL,
-- but the single global row it was reshaping was already gone by then.
--
-- Every function that reads these settings starts by asking for the row and
-- refusing when it is missing, so this is why the first-order offer answered
-- "Welcome offer is unavailable." for every customer on every cart, and why a
-- free-delivery voucher answered "Delivery is already free on this order." for
-- every customer too.
--
-- `on conflict do nothing` rather than `do update`: this only fills a gap. Once
-- a branch manager has set their own hours, fee or offer in the admin panel, a
-- re-run of this migration must not quietly put the defaults back. The column
-- defaults below are what a brand-new row would get anyway, so stating them
-- keeps the intent visible rather than hiding it in the schema.

insert into public.store_settings (branch_id)
select b.id
  from public.branches b
 where not exists (
   select 1 from public.store_settings s where s.branch_id = b.id
 );

comment on table public.store_settings is
  'Per-branch settings: delivery fee, opening hours, the first-order welcome offer and every '
  'loyalty rate. Each branch decides its own — seeded from the column defaults by '
  '20261007110000_seed_store_settings_per_branch.sql, then editable in the admin panel. A branch '
  'with no row here is treated as closed: every settings-reading function refuses rather than '
  'assuming a default, so a missing row disables offers rather than granting them.';