# Rider Panel - Design

## 1. Problem

The rider side of the app is one page of hardcoded demo data. `rider_screen.dart` is 956
lines of made-up content: a frozen `todayEarnings = 2450.0`, invented customers, and an
in-memory `orderFlowProvider` (`StateNotifier<List<DemoOrder>>`) that never touches
Supabase and loses everything when the app closes.

Meanwhile the database already has the rider domain modelled and empty:

| Table | Rows | Shape |
|---|---|---|
| `rider_details` | 0 | `profile_id` PK, `branch_id`, `status` in `available\|on_delivery\|offline` |
| `rider_assignments` | 0 | `order_id`, `rider_id`, `status` in `assigned\|picked_up\|delivered\|failed`, `assigned_at`, `picked_up_at`, `delivered_at` |
| `order_status_history` | 0 | `order_id`, `status`, `changed_by`, `changed_at` — never written |

No rider has ever been onboarded: `rider@test.com` has `profiles.role = 'rider'` but zero
rows in `rider_details`, so there is no branch and no status for them to work against.

Rider accounts are created by the owner in the Next.js panel. Riders never self-register.
The customer app is done; the rider app is the remaining half.

## 2. Goals

- The rider panel reads and writes **real** rows. No demo data survives.
- A rider logs in and lands on a screen driven entirely by their own assignments.
- Availability, accept, decline, pick-up, deliver, and fail are **server-enforced
  transitions** — an illegal jump is impossible even if the phone is tampered with.
- `orders.status`, `rider_assignments.status` and `order_status_history` can never
  disagree with each other.
- Riders can only ever see and touch **their own** jobs. Customers keep only their own
  orders. The owner panel keeps full access, unchanged.
- A rider never gains access to customer profile rows.
- Riders keep the drawer navigation the customer app already uses.

## 3. Non-goals (deliberately excluded)

- **Branch manager role.** Only `owner` operates the panel for now.
- **Proof of delivery** (photo, signature, customer OTP). Disputes are handled in the
  panel; the rider app does not capture evidence in v1.
- **Penalty / strike system** driven by customer complaints. Needs a penalty counter on
  `rider_details`, owned by the panel side.
- **Push notifications.** No Firebase project exists, so FCM tokens cannot be obtained.
  `firebase_core` / `firebase_messaging` also need a `google-services.json` that cannot be
  generated here. Adding an empty `push_tokens` table now would be dead weight, so it is
  deferred entirely — see §9 for what replaces it and §12 for when push returns.
- **Rider-facing navigation inside the app.** "Open in Maps" is a link out; there is no
  turn-by-turn map (the app has no Maps SDK).
- **Migrating the customer app's own RLS gaps.** `menu_items` currently has
  `Public insert/update/delete` policies granting write to `role public`. That is a
  separate, real vulnerability and is called out in §12, not fixed here.

## 4. Data layer

All DDL is applied as reviewed migration SQL, never by hand in the SQL editor.

### 4.1 Delivery contact must be snapshotted onto the order

This is the blocking discovery. `profiles` and `addresses` both have RLS restricted to own
rows, so a signed-in rider **cannot read the customer's name, phone or address**. `orders`
stores only `customer_id` and `address_id` references. Under the policies in §4.5 the
rider would receive a job with no address and nobody to call.

Rather than granting riders read access to customer profiles, the delivery details are
copied onto the order at checkout:

```sql
alter table public.orders
  add column customer_name   text,
  add column customer_phone  text,
  add column delivery_address text,
  add column delivery_latitude  numeric,
  add column delivery_longitude numeric;
```

`checkout_screen.dart` populates all five from the selected address and the customer's
profile at the moment the order is placed. This is also correct on its own terms: a customer
can edit or delete their saved address after ordering, and a rider must deliver to the
address that was actually ordered, not to whatever the customer has since changed it to.

The rider reads these columns from the one order row they are assigned. No customer profile
row is ever exposed to a rider.

### 4.2 `rider_assignments` — widen the status check

Accept and decline are both currently unrepresentable. The full lifecycle needs six states:

```sql
alter table public.rider_assignments
  drop constraint rider_assignments_status_check;

alter table public.rider_assignments
  add constraint rider_assignments_status_check
  check (status in ('assigned','accepted','picked_up','delivered','declined','failed'));
```

Lifecycle: `assigned → accepted → picked_up → delivered`, with `declined` reachable only
from `assigned` and `failed` reachable from `accepted` or `picked_up`.

`orders.status` moves `out_for_delivery` on pick-up and `delivered` on completion. The
`in_kitchen` state remains the panel's to set.

### 4.3 Rider payout — one configurable number

The payout per delivery is not yet decided by the business, so it is stored rather than
hardcoded. `store_settings` already holds the customer-facing `delivery_fee`; the rider
rate sits beside it:

```sql
alter table public.store_settings
  add column rider_payout_per_delivery numeric not null default 250;
```

250 is a placeholder carried over from the demo screen and **must be confirmed** (§12).
Rider earnings are `delivered assignments × store_settings.rider_payout_per_delivery`.
`orders.delivery_charges` is deliberately **not** used — that is what the customer pays,
which is not the same thing.

A per-rider rate is possible later by adding a nullable override column to `rider_details`;
it is not built now.

### 4.4 Transition functions

Six `SECURITY DEFINER` functions. `SECURITY DEFINER` + `set search_path = public` matches
the existing `is_staff()` / `is_owner()` pattern already in the database. Each function
validates ownership with `auth.uid()`, performs the transition with `FOR UPDATE` so two
racing taps cannot both win, writes `order_status_history`, and returns the updated row.

| Function | From | To | Also does |
|---|---|---|---|
| `rider_claim_offer(uuid)` | `assigned` | `accepted` | `rider_details.status → on_delivery` |
| `rider_decline_offer(uuid)` | `assigned` | `declined` | `rider_details.status → available`; leaves `orders.status` untouched so the order stays claimable by the panel |
| `rider_mark_picked_up(uuid)` | `accepted` | `picked_up` | sets `picked_up_at`; `orders.status → out_for_delivery`; writes history |
| `rider_complete_delivery(uuid)` | `picked_up` | `delivered` | sets `delivered_at`; `orders.status → delivered`; `rider_details.status → available`; writes history |
| `rider_fail_delivery(uuid, text)` | `accepted`\|`picked_up` | `failed` | `orders.status → confirmed`; frees the rider; writes history |
| `rider_set_availability(text)` | — | — | writes own `rider_details.status`; refuses `available` while an active job exists |

`order_status_history` is written only by the three functions that change `orders.status`.
Accept and decline are rider-side decisions about an assignment, not changes to the order,
so recording them in order history would misrepresent it. The assignment row's own `status`
is the record of those two.

Every function raises a specific exception on a rejected transition, so the UI can show
"this delivery is no longer yours" rather than a generic failure.

Riders get **no direct `UPDATE`** on `rider_assignments`, `rider_details` or `orders` at
all — RLS denies it and these functions are the only path.

### 4.5 Row Level Security

RLS is currently **disabled** on 8 tables, so any holder of the publishable key — which is
baked into the shipped APK — can read and modify every row. Enabling RLS without policies
blocks all access, so the policies below ship in the same migration as the
`enable row level security` statements.

The panel needs no key change. Both panel accounts (`admin@mrpizza.com`,
`mrpizzapak@gmail.com`) are real `auth.users` rows present in `admin_users` with
`role = 'owner'`, and `is_staff()` already gates their access on the tables that have RLS
today. The same helper is reused here.

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `orders` | own order, assigned order, or `is_staff()` | `customer_id = auth.uid()` | `is_staff()` | none |
| `order_items` | parent order visible to caller | parent order owned by caller | `is_staff()` | `is_staff()` |
| `order_status_history` | parent order visible to caller | `is_staff()` | none | none |
| `rider_details` | own row or `is_staff()` | `is_staff()` | none (availability RPC only) | `is_staff()` |
| `rider_assignments` | `rider_id = auth.uid()` or `is_staff()` | `is_staff()` | none (RPCs only) | `is_staff()` |
| `branches` | everyone (public info) | `is_staff()` | `is_staff()` | `is_staff()` |
| `transactions` | own order or `is_staff()` | `is_staff()` | `is_staff()` | none |
| `loyalty_ledger` | `user_id = auth.uid()` or `is_staff()` | `is_staff()` | none | none |
| `store_settings` | already `is_staff()`-gated | unchanged | unchanged | unchanged |

"Assigned order" means `exists (select 1 from rider_assignments where order_id = orders.id
and rider_id = auth.uid())`. `profiles` and `addresses` are deliberately left as own-rows-
only; §4.1 is what makes that workable for riders.

## 5. New code

### 5.1 `lib/features/rider/models/`

- `rider_availability.dart` — `enum RiderAvailability { offline, available, onDelivery }`
  with a parser for the `rider_details.status` text column.
- `rider_delivery.dart` — one assignment joined to its order and branch:
  `assignmentId`, `orderId`, `billNumber`, `assignmentStatus`, `orderType`, `customerName`,
  `customerPhone`, `deliveryAddress`, `deliveryLatitude`, `deliveryLongitude`, `branchName`,
  `branchAddress`, `itemSummary`, and the three timestamps. Customer details come from the
  §4.1 snapshot columns, never from a customer profile lookup.

### 5.2 `lib/features/rider/logic/delivery_actions.dart` (pure)

Maps an assignment status to what the rider may do next. Kept free of Flutter and Supabase
so it is directly unit-testable:

- `primaryActionFor(status)` → the one big button's label and which RPC it calls
- `offersFor(deliveries)` / `activeFor(deliveries)` / `historyFor(deliveries)` — the three
  buckets the dashboard renders
- `earningsFor(deliveries, payoutPerDelivery)` — completed count times the configured rate

### 5.3 `lib/features/rider/data/rider_repository.dart`

One method per transition, each calling its named function, plus `fetchRiderDetails()`,
`fetchDeliveries()` and `fetchPayoutRate()`. No direct table writes.

### 5.4 `lib/features/rider/providers/rider_providers.dart`

`riderDetailsProvider` (Future), `riderDeliveriesProvider` (Stream — §9), `payoutRateProvider`
(Future), `riderAvailabilityProvider` and `riderEarningsProvider` (derived). Mutations
invalidate `riderDeliveriesProvider` so the dashboard re-reads from the database rather
than patching local state optimistically — the database is the only truth.

### 5.5 Screens

- `rider_screen.dart` — **rewritten** as the dashboard: availability toggle, today's strip
  (completed count + payout), the active job card with Call / Open in Maps / primary
  action, pending offers with Accept / Decline, recent deliveries preview.
- `rider_history_screen.dart` — full delivered list.
- `rider_earnings_screen.dart` — per-day totals from the configured rate.

`app_drawer.dart` becomes role-aware: a rider sees Deliveries, Earnings, Profile, Support,
Logout. The customer item list is unchanged. The hidden triple-tap-to-`/rider` affordance is
removed — the drawer and the route guard already cover rider access.

Routes `/rider/history` and `/rider/earnings` are added to `riderOnlyLocations`.

### 5.6 Customer-side change required

`checkout_screen.dart` must write the five snapshot columns from §4.1 when it creates the
order. Without this, every new order is undeliverable. This is the one piece of the work
that touches the finished customer app, and it is covered by its own test.

## 6. Data flow

1. Rider signs in. `roleProvider` resolves `profiles.role = 'rider'`, router lands on
   `/rider` (already implemented).
2. Dashboard reads `rider_details` for `auth.uid()`.
   **No row** → "Your rider account isn't set up yet — contact the branch." A blocked
   state, not a crash and not an empty dashboard. This is `rider@test.com` today.
3. Dashboard subscribes to the rider's own `rider_assignments` rows and reads them joined
   to `orders` and `branches`.
4. Primary button calls one function. On success the stream re-reads.
5. `rider/test.com` needs a `rider_details` row seeded by the panel before the screen shows
   anything but the setup message.

## 7. Error handling

| Situation | Behaviour |
|---|---|
| No `rider_details` row | Blocking "not set up yet" message with a retry |
| Rejected transition (someone else took it, or already completed) | Show the function's message; refresh the list. Never a silent no-op |
| Network failure mid-mutation | Unknown server state → refresh and show the true state rather than assuming failure |
| Realtime disconnected | Dashboard falls back to pull-to-refresh and shows a quiet "offline" hint |
| `rider@test.com` signed in during development | Setup message, not a stack trace |
| Load error | Retry button, error text in plain language |

## 8. Testing

1. **Pure logic** (`delivery_actions.dart`) — every status maps to the right action;
   buckets partition the list correctly; a delivery cannot be in two buckets; earnings use
   the configured rate and ignore undelivered jobs.
2. **Repository** — each transition calls its function; no method issues a direct
   `update` on `rider_assignments`, `rider_details` or `orders`.
3. **Widget** — dashboard renders in each of five states: no account, offline, available
   with no offers, one pending offer, active job at each of accepted / picked_up.
4. **Checkout snapshot** — placing an order writes all five §4.1 columns from the selected
   address and customer profile.
5. **Regression guard** — the existing 179 tests stay green, and a test asserts a
   non-rider cannot reach any rider route.

## 9. How a rider learns about new work (replaces push)

Without a Firebase project there is no way to notify a rider whose app is closed, so this
is an honest limitation rather than something to paper over.

v1 uses a **Supabase Realtime subscription** on `rider_assignments` filtered to
`rider_id = auth.uid()`, plus pull-to-refresh. `supabase_flutter` already includes
realtime, so this needs no new dependency and no external service.

Limitation, stated plainly: a rider with the app closed will not be told about a new
assignment. They see it the next time they open the app. FCM push is the fix for that and
returns when a Firebase project exists — it needs a `push_tokens` table, an Edge Function
to send, and `google-services.json`.

## 10. Delivery phases

This spec is one feature but it lands in three reviewable phases, so the database is never
half-changed and the UI is never wired to a schema that is not ready:

1. **Schema and access** — §4.1–§4.5. Migrations, RLS policies, transition functions, plus
   committing the `is_staff()` / `is_owner()` definitions. Verifiable with SQL against the
   live database before any Dart is touched. *Requires explicit permission.*
2. **Data layer and checkout snapshot** — §5.1–§5.4 and §5.6. Models, pure logic,
   repository, providers, and the checkout columns, with unit tests against a fake Supabase.
3. **UI** — §5.5. Dashboard, history, earnings, role-aware drawer, routes, realtime, plus a
   `rider_details` row seeded for `rider@test.com` so the screen is testable.

## 11. Verification before completion

- `flutter analyze` clean
- `flutter test` green, including the new suites
- Applied against the real project only after explicit written permission, one migration at
  a time, with the RLS policies in the **same** migration as the `enable row level security`
  statements so the database is never left in a blocked state
- Manual pass: customer places an order → snapshot columns written → owner creates
  `rider_details` → owner assigns the order → rider sees it, accepts, picks up, delivers →
  `orders.status`, `rider_assignments.status` and `order_status_history` all agree
- Confirm the customer app is unaffected: order placement, tracking and checkout still work
  under the new policies

## 12. Open items and risks

- **Rider payout is a placeholder.** `store_settings.rider_payout_per_delivery` defaults to
  250, carried over from the demo. The earnings screen is only as honest as this number.
  Confirm the real rate before showing earnings to a rider.
- **Riders cannot be notified while the app is closed.** See §9. This is the main gap in
  v1 and the reason push is on the list as soon as a Firebase project exists.
- **The panel must populate `rider_details`.** The owner creates the account; something must
  insert the `rider_details` row with `branch_id`, or every rider sees the "not set up"
  message forever. Whoever builds that panel needs to know.
- **The panel should collect a rider phone number.** Riders call customers, so the customer
  number is what the app needs, and that comes from `profiles.phone` at checkout. The rider's
  own number is for the panel to reach them and is not required by v1.
- **`menu_items` is writable by `role public`.** Anyone with the app key can currently
  insert, update and delete menu items. Pre-existing, unrelated, and worth its own fix.
- **Customers cannot delete an address that has orders on it.** `orders.address_id` is
  `ON DELETE NO ACTION`, so deleting a used address raises a foreign key error instead of
  succeeding. The §4.1 snapshot removes the reason to keep the reference, so changing this
  to `ON DELETE SET NULL` is a clean follow-up — but the panel may join on `address_id`, so
  it is not changed here without checking their code.
- **`is_staff()` / `is_owner()` exist only in the live database.** No migration in the repo
  creates them. A database rebuilt from migrations loses them and breaks every policy that
  calls them. This spec's migrations should also commit the definitions.
- **Payment is untouched.** Cash on delivery and Safepay settlement are not in scope.
