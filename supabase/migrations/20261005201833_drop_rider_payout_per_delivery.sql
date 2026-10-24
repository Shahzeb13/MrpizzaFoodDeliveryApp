-- Riders are paid a fixed monthly salary by the branch, not a rate per
-- delivery. The per-delivery figure the rider app showed was never a number
-- the branch agreed to and could not honour, so the column goes.
--
-- Nothing in the database read this column: no function and no view referenced
-- it. The only reader was RiderRepository.fetchPayoutRate() in the Flutter app,
-- which has been deleted along with the earnings screen and its route.
--
-- The delivery count a rider sees (day / week / month) is computed by the
-- Next.js admin panel from rider_assignments, and is unaffected.

alter table public.store_settings
  drop column if exists rider_payout_per_delivery;
