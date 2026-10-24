# Flutter App Agent Brief — Branch Separation (MrPizza App)

You are working on the **MrPizza** Flutter app. Read `AGENTS.md` first — it has the
safety rule (no Supabase writes without permission), the code-style rules
(feature-first structure, self-documenting names), and the testing rules
(**targeted tests only**, never the full suite after a small change).

## Project

- Flutter, Riverpod (`flutter_riverpod` 2.6.1), Supabase client
- Structure: `lib/features/<feature>/{data,models,providers,screens}`
- Runs on Android + iOS. Ships a publishable anon key inside the APK.
- Two branches: **Abbottabad (ABT)** and **Mansehra (MSH)**. Menu is identical for both
  by team decision; **delivery fee, store hours, welcome offer, and loyalty rates differ
  per branch.**
- Roles: `customer`, `rider`, and admin (`branch_manager`) — the `owner` role is being
  removed. Admins use the **separate Next.js panel**, not this app.

## Critical context

**The database is mid-refactor.** Several things you depend on are changing or have
already changed. Read `panelprompt.md` for the full database-side plan.

Already done:

- `create-rider-account` edge function → v6 (branch-scoped, `branch_manager` only).
- `rider_details.status` **dropped**. The column no longer exists.
- Rider availability toggle removed from the app.

In flight (may land while you work):

- **RLS is being enabled** on `orders`, `order_items`, `order_status_history`,
  `transactions`, `rider_details`, `rider_assignments`, `branches`. Today it is
  **off**, so the app currently reads those tables unguarded. Once on, unscoped
  queries return nothing or error.
- `store_settings` becomes **per-branch**. Its shape changes from one global row to
  keyed by branch.
- `redeem_voucher` loses its caller-supplied `p_user_id`.

**Design every change so it works after RLS is on.** Do not write new queries that
depend on reading a table without filtering it.

## Task 1 — `store_settings` is now per-branch

Today the app reads it globally. File: `lib/features/rider/data/rider_repository.dart:181`
selects `rider_payout_per_delivery` from `store_settings` with no filter. That will
silently read the wrong branch's rate once rows are split.

The rider app must read **its own branch's** settings, scoped via
`rider_details.branch_id`.

Also find and fix every other read of `store_settings`:
- `delivery_fee` → charged at checkout
- `store_open`, `order_open_time`, `order_cutoff_time` → store-hours gating
- `first_order_*` → welcome offer
- `loyalty_*` → loyalty rates

⚠️ The PK may change from `id = 1` to `branch_id`. The customer app has no
`branch_id` of its own — a customer's branch comes from the **order they are placing**,
resolved by `BranchSelection` / nearest-branch logic. Get this right: the fee and
welcome offer shown at checkout must come from the branch that will fulfil the order.

Confirm the exact new shape before coding — ask if unclear.

## Task 2 — Filter every query by branch

Once RLS is on, any query not scoped to the caller's branch returns **nothing**, and
you get silent empty screens rather than errors.

Audit and fix, at minimum:

- `orders`, `order_items`, `order_status_history` — filter by the caller's own branch
- `rider_details` — already filters `profile_id` (good, keep it)
- `rider_assignments` — branch is derivable via `assignment → order → branch`
- `rider_deliveries()` — already branch-aware (the only rider function that is)
- Admin-side screens if any exist in this app

**Never hardcode a branch id.** Read it from the authenticated user's row.

## Task 3 — Rider: no cross-branch leakage

The rider must never see or claim another branch's order.

- The DB now rejects cross-branch claims (guard added in the six `rider_*` functions).
- The app should not need changes if it uses `rider_deliveries()` — **verify** it does,
  and verify `rider_repository.dart` has no direct `rider_assignments` reads.
- Surface the database's refusal message to the rider in plain words rather than a
  generic failure.

## Task 4 — Handle the removed availability toggle

Already done this session — **verify, do not redo**:

- Deleted `lib/features/rider/models/rider_availability.dart`
- Deleted `_AvailabilityToggle` from `rider_screen.dart`
- Deleted `riderAvailabilityProvider` and `RiderAvailabilityController`
- Deleted `RiderRepository.setAvailability()`
- `RiderDetails` no longer has `availability`
- `fetchRiderDetails()` no longer selects `status`
- `test/rider_availability_test.dart` deleted

If you find leftover references to `status` / `availability` in the rider feature,
remove them.

## Task 5 — Testing

**Targeted only.** Run the rider and payment tests you touch, not the whole suite:

```bash
flutter test test/rider_dashboard_test.dart test/rider_providers_test.dart test/rider_repository_test.dart test/rider_history_and_earnings_test.dart
```

Run `flutter analyze` only when the change is broad enough to justify it. Do not fix
unrelated warnings or deprecations. Format only files you changed.

Write a test for each branch-scoped read you add — specifically that a filter is
present, so a regression cannot silently drop it.

## Style rules

- Feature-first layout; shared code in `lib/app/` and `lib/core/`.
- Self-documenting names. Banned: `handleData`, `process`, `update`.
  Use `fetchOrderById`, `buildRiderStatusBadge`, `calculateDeliveryFee`.
- Prefer fewer taps for ordering — skip the item detail screen for simple items.
- UI priority: minimise taps.
- Match the surrounding file's existing style. Read before editing.

## Constraints — do not touch

- Payment callback / webhook handlers
- Role and authorization guards (the database owns these now)
- RLS policies
- Production schema or data
- Order and payment state transitions
- Never commit secrets, API keys, or the service-role key
- Do not add a `safepay_flutter` package — no official SDK exists

## Known gotchas

- Mapbox geocoding runs on the same `pk.` token as the map; make sure that token has the geocoding scope enabled or the address box never fills.
- Location failure must never block checkout; manual address entry stays usable.
- A hand-typed address clears the GPS pin.
- Only `CheckoutState.branchIsNearest` may label a branch "nearest".
- Never hardcode "nearest".
- Do not use `OrdersRepository.bundledBranches` for anything hitting the database —
  those ids are not real UUIDs and will fail the `orders.branch_id` FK.

## Definition of done

1. Rider sees his own branch's payout rate, never another branch's.
2. Customer checkout shows the fulfilling branch's delivery fee and welcome offer.
3. Store-hours gating uses the correct branch's hours.
4. Loyalty rates come from the correct branch's settings.
5. No screen goes silently empty because a query lost its branch filter.
6. Every new branch-scoped read has a test asserting the filter exists.
7. `flutter test` on the touched files passes.