-- At most one active delivery per rider.
--
-- The rider dashboard shows a single active job card, so the data has to
-- guarantee there is only ever one active job. Nothing in the schema enforced
-- that: the panel could assign a rider a second order while they were already
-- out, and the second job would be invisible on the dashboard.
--
-- A partial unique index constrains only the active rows, so a rider can hold
-- any number of finished or declined assignments and still only one live job.
-- The panel now gets a constraint violation when it tries to give a rider a
-- second job, which is the correct outcome: the owner can see the rider is busy.

create unique index if not exists rider_assignments_one_active_per_rider
  on public.rider_assignments (rider_id)
  where status in ('accepted', 'picked_up');
