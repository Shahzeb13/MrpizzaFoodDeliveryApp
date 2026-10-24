# Panel Agent Brief — Branch Separation (Supabase + Next.js Admin Panel)

You are working on the **MrPizza** admin panel agent task. Read `AGENTS.md` first — it
contains a hard safety rule: **never run a Supabase write without explicit human
permission.** Read-only queries are fine. Present SQL, then wait.

## Project

- Supabase project: `eytsownrsujphibqpimt` ("foodApp", ap-southeast-1, PG 17.6)
- Two branches: **Abbottabad (ABT)** and **Mansehra (MSH)**
- Admin panel is a **separate Next.js repo, not in this workspace.** You are editing
  the *database* side here; the panel repo must be changed in parallel by the human.
- Pre-launch. No production data loss risk, but real test orders exist (34).

## Goal

Branch isolation that is airtight. A branch manager sees **only his branch's** orders,
riders, vouchers, and settings. Nothing leaks sideways. The `owner` role is being
**removed entirely** — there is exactly one admin role now: `branch_manager`.

## Accounts already created

| Email | Password | Role | Branch |
|---|---|---|---|
| `manager@abbottabad.com` | `Abbottabad#Mgr2026` | `branch_manager` | ABT |
| `manager@mansehra.com` | `Mansehra#Mgr2026` | `branch_manager` | MSH |

Two legacy accounts remain `role='owner'` with `branch_id = NULL`:
`admin@mrpizza.com`, `mrpizzapak@gmail.com`. The human decides whether to convert
or delete them — **do not touch them without permission.**

Branch UUIDs: ABT `04b2febe-d3d5-4a6a-be51-b1bdfe02286a`,
MSH `300759e7-1c2c-4c1c-85e2-8f531c57e823`.

## Work already completed this session — do not redo

- `create-rider-account` edge function is at **v6**. It already:
  - requires `role = 'branch_manager'`
  - reads the branch from the caller's own `admin_users.branch_id`, ignoring any sent value
  - `list` returns only the caller's branch riders
  - `set_branch` / `remove` reject riders outside the caller's branch
  - has **no** `set_status` action (`rider_details.status` was dropped)
- Migration `rider_drop_self_service_availability` applied. `rider_details` is now
  just `profile_id, branch_id`.
- Flutter rider availability toggle removed (separate brief, `appprompt.md`).

## Task 1 — Replace `is_staff()` with branch scoping

`public.is_staff()` is currently:

```sql
select exists (select 1 from public.admin_users where id = (select auth.uid()));
```

It asks *"is this person an admin at all"* and **never checks the branch**. So today a
Mansehra manager can read and edit all 34 Abbottabad orders. This is the core defect.

Create the anchor function, then make every policy key off it:

```sql
create or replace function public.my_branch_id()
returns uuid language sql stable security definer
set search_path to 'public' as $$
  select branch_id from public.admin_users where id = (select auth.uid())
$$;
```

Suggested companions (names are yours to choose, keep them self-documenting):

- `is_branch_manager()` — caller has any `admin_users` row
- `can_manage_branch(target uuid)` — caller manages `target`, returns false for null

Keep `my_branch_id()` returning only the UUID. **Never return the branch id as the
function's boolean/result when a policy could leak it.**

## Task 2 — Enable RLS on the 7 unprotected tables

These have **RLS disabled** and `anon` holds full table grants, so the publishable key
baked into the shipped APK can read and modify every row — customer names, phones,
delivery addresses, rider assignments:

`branches`, `orders`, `order_items`, `order_status_history`, `transactions`,
`rider_details`, `rider_assignments`

**A ready-made file already exists and was never applied:**
`supabase/migrations/20260928092000_rider_rls_policies.sql` (224 lines). It enables
RLS with customer/rider/panel policies. It is absent from the applied migration
history and the tables are still unprotected — confirm this, then adapt it rather than
writing from scratch. Replace its `is_staff()` calls with your branch-scoped helpers
so a manager only matches his own branch.

⚠️ Enabling RLS with no policies blocks every client, including the panel. Each
`enable row level security` must ship with its policies in the same migration.

⚠️ `orders`, `order_status_history`, `rider_assignments` are in the
`supabase_realtime` publication. With RLS off, anyone can subscribe and receive a live
feed of **every** order. Fixing RLS fixes this — verify it after.

## Task 3 — Branch-scope `store_settings`

Currently **one global row** with `CHECK (id = 1)`, 16 columns. The human confirmed
these differ per branch and must be split:

- `delivery_fee`
- store hours: `store_open`, `order_open_time`, `order_cutoff_time`
- welcome offer: `first_order_discount_enabled`, `first_order_discount_pct`,
  `first_order_max_cap`, `first_order_min_subtotal`
- loyalty rates: `loyalty_enabled`, `loyalty_rupees_per_point`,
  `loyalty_min_order_total`, `loyalty_max_points_per_order`, `loyalty_redemption_value`
- `rider_payout_per_delivery` — read directly by the rider app
  (`rider_repository.dart:181`)

Design decision needed from the human: **replace the single row with one row per
branch (PK becomes `branch_id`), or keep a global default plus per-branch overrides?**
`admin_loyalty_overview` hardcodes `where s.id = 1` — it must be updated.
`rider_repository.dart:181` reads this table with no branch filter — it must filter by
the rider's own `rider_details.branch_id`.

## Task 4 — `menu_items`: keep shared

The team decided **the menu is identical for both branches.** Do **not** duplicate the
88 rows per branch. Leave `menu_items` global. If you later want per-branch
availability only, that is a small addition — but not now.

## Task 5 — Close two live security holes

**a) `menu_items` has three leftover public policies** (roles `{public}`, `qual=true`,
`with_check=true`): `Public insert menu_items`, `Public update menu_items`,
`Public delete menu_items`. Anyone with the anon key can reprice or wipe the menu.
Likely debris from migration `remove_temporary_menu_image_upload`. Propose dropping
them.

**b) `redeem_voucher(p_code, p_order_id, p_user_id)` is the worst hole in the database.**
It is `SECURITY DEFINER`, `EXECUTE`-granted to **`anon`**, and does:

```sql
v_user uuid := coalesce(p_user_id, auth.uid());
```

with **no check that `p_user_id = auth.uid()`, no branch check, and no order-status
check**. An unauthenticated caller can pass any `order_id` and drive that order's
`total` to ~0. It writes `orders` and `voucher_redemptions` as definer, bypassing RLS.

Fixes needed: ignore the caller-supplied `p_user_id` and use `auth.uid()`; require the
order to belong to the caller; require the order to be in a payable state; scope to
the order's branch.

**Also:** `validate_voucher` and `validate_first_order_discount` are anon-executable
with a caller-supplied `p_user_id`, letting anyone enumerate whether an arbitrary user
has ever ordered.

## Task 6 — Rider functions must check the branch

None of the six `rider_*` transition functions mention `branch` except `rider_deliveries`
(the read function). So **an Abbottabad rider can claim a Mansehra order today** —
nothing compares `rider_details.branch_id` to `orders.branch_id`.

Add the guard to each: `rider_claim_offer`, `rider_mark_picked_up`,
`rider_complete_delivery`, `rider_decline_offer`, `rider_fail_delivery`. Reject when
the rider's branch differs from the order's branch. This is what makes "a rider never
sees the other branch's orders" true rather than hoped-for.

## Task 7 — Drop the `owner` / `staff` roles

- `admin_users_role_check` is `role = ANY (ARRAY['owner','branch_manager','staff'])`.
  Narrow it to `branch_manager` only — **but check the Next.js panel first**, since it
  may still offer those options and inserts will then fail.
- Add `check (role = 'branch_manager' or branch_id is not null)` so a manager can never
  exist without a branch.
- `is_owner()` is used by 3 `admin_users` policies and becomes dead — plan its removal.
- 15 policies across 9 tables call `is_staff()`. Consider renaming it `is_admin()`,
  but that touches ~15 policies — propose it, don't assume.
- Consider preventing `rider_details.branch_id` updates after insert (a rider is locked
  to one branch; RLS is currently off so anyone with the app key can re-point one).

## Task 8 — Data integrity notes

- **7 orders are `status='delivered'` while their `rider_assignments` row is not.**
  Order status and assignment status disagree. Probably test data, but reconcile or
  document it.
- `bill_serial_counters` has **1 row (ABT only)**. The MSH row is created lazily by
  `next_bill_serial_number()`, so it will appear on first MSH order — verify this path.
- No indexes on most FK columns: `order_items.menu_item_id`, `orders.address_id`,
  `orders.rider_id`, `addresses.user_id`, `loyalty_ledger.order_id`,
  `voucher_redemptions.{voucher_id,user_id,order_id}`, `order_alerts.order_id`,
  `transactions.order_id`, `rider_assignments.order_id`. Also none on `orders.created_at`.
- `transactions` is **empty** and there are **no Safepay edge functions** — payments are
  not built. Nothing is webhook-protected yet.
- `profiles` has duplicate SELECT-own-row policies.
- 4 of 34 orders have no `order_status_history` rows.

## Task 9 — Fix repo / live-database drift

The repo's migration filenames and the applied versions are **different series**:
repo `20260928090000_rider_panel_foundation.sql` was applied to the live DB as
`20260929114645`. Most of this database exists **only in the live DB**. Reconcile the
history so a rebuild is possible and future migrations do not collide. Write new
migrations into `supabase/migrations/` so the repo stays the source of truth.

## Definition of done

1. Both managers log into the panel successfully.
2. ABT manager sees 34 ABT orders; MSH manager sees 0 (no MSH orders exist yet).
3. ABT manager **cannot** read, edit, or delete any MSH row — and vice versa.
4. An Abbottabad rider cannot claim or see a Mansehra order.
5. `anon` can no longer read or write `orders`, `order_items`, `transactions`,
   `rider_details`, `rider_assignments`, `order_status_history`.
6. Realtime no longer broadcasts other branches' orders.
7. `redeem_voucher` cannot be called anonymously to zero out an order.
8. Each branch reads its own delivery fee, hours, welcome offer, and loyalty rates.
9. Every change is in a migration file in the repo.
10. Write a leak-test script and run it — do not claim isolation you have not tested.

## Ground rules

- Present every migration as SQL and **wait for explicit approval** before applying.
- Never touch payment code, RLS on `transactions`, or the two legacy `owner` accounts
  without permission.
- When you enable RLS, enable it **with** its policies in the same migration.
- Report unrelated findings separately instead of expanding scope.