-- Live updates for the rider dashboard.
--
-- onPostgresChanges on a table that is not in the realtime publication silently
-- never fires: no error, no warning, the subscription just sits there doing
-- nothing. The live supabase_realtime publication was verified to have an
-- explicit, empty table list, so rider_assignments has to be added to it.
--
-- The publication is what the app already authenticates against, so this needs
-- no new configuration. RLS still decides which rows a rider actually receives,
-- and the client-side filter on rider_id narrows the traffic further.

alter publication supabase_realtime add table public.rider_assignments;

-- The dashboard reloads this rider's whole assignment list on every change, and
-- that list is fetched with `where rider_id = auth.uid()` ordered by
-- assigned_at. Neither the primary key nor the partial unique index serves that
-- query, so it was a sequential scan on every pull-to-refresh.
create index if not exists rider_assignments_rider_assigned_at_idx
  on public.rider_assignments (rider_id, assigned_at desc);
