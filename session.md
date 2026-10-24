# Session Handoff

## Current chat

```
ses_ec6448eb2ffekAwxcloyA0SGuW
```


hey! i am having an issue regarding app! so right now if i go to payfast page and then come back! it redeicts me to the page whre online and cod options  are shown! but their is an issue! the status bar on the menu screen is bugging out! fox exampe if i am ordering abt-072 and go to payfast payment and go back! their is no order created right ! so their is no order abt-072 in the datbase! but the status bar show an order! and also the bill serial table in the supbase also increments! diagnose why this happens and then fix it ! thanks

**Project:** MrPizza — `G:\ElectronApps\mrpizza`
**Session store:** `C:\Users\Mr-Imperfect\.local\share\opencode\opencode.db`

## How to resume

```bash
opencode --continue                                # most recent
opencode --session ses_ec6448eb2ffekAwxcloyA0SGuW  # this one
opencode session list                              # all sessions
```

In the **opencode desktop app**, open `G:\ElectronApps\mrpizza` and pick this session.

Fallback:
```bash
opencode export ses_ec6448eb2ffekAwxcloyA0SGuW -o session.json
opencode import session.json
```

From a phone or second machine:
```bash
opencode serve --port 4096 --hostname 0.0.0.0   # set OPENCODE_SERVER_PASSWORD first
opencode attach http://<pc-ip>:4096
```

---

# STATUS: online payment works END TO END. Proven with a real PayFast transaction.

`flutter analyze` clean · **479 tests pass** · profile APK builds

---

## What is DONE and verified

### Real transaction, real PayFast IPN (17 Oct 2026)

```
✅ Tap "Continue with Payment" → payment screen with two options
✅ Online Payment → order created, token fetched from PayFast UAT
✅ PayFast page opens in the WebView
✅ Test card completes the payment
✅ PayFast SERVERS → IPN → payfast-ipn     ← real, not simulated
✅ validation_hash matched                 ← SIGNING FORMULA IS CORRECT
✅ err_code 000
✅ payments row → paid, with PayFast's transaction_id
✅ orders row  → paid
✅ Amount matched exactly (2043.94 = 2043.94)
```

Log line seen: `IPN 79f6b58f-mvcarbhd 000 paid` → order **ABT-066**, now `delivered` /
`paid`. Proof order left in place on purpose.

**The signing formula is no longer a risk.** It came from PayFast's engineer AND a
real IPN passed it. That earlier uncertainty is closed.

### Database — 6 migrations applied

| File | What |
|---|---|
| `20261014090000_payfast_payments.sql` | `payments`, `orders.payment_status`, `apply_payment_result` |
| `20261015090000_payfast_multi_attempt_payments.sql` | multi-attempt, `double_paid`, `payments_one_paid_per_order` |
| `20261016090000_cash_on_delivery_payment_method.sql` | `orders.payment_method`, `mark_cash_collected` |
| `rider_deliveries_payment_columns` | `payment_method`/`payment_status` on the rider read |
| `discard_unpaid_order` | roll back an abandoned online order, releasing its bill serial |
| `collect_pickup_order` | close a pickup order out in one action: collected **and** (if cash) paid |

**Schema facts worth remembering**

| Reference assumed | Reality |
|---|---|
| `orders.id uuid` | ✅ matches |
| `orders.user_id` | **`orders.customer_id`** → `profiles.id` → `auth.users.id` |
| `orders.total numeric` | ✅ matches |
| `orders.payment_status` | did not exist, added |

- The basket id is **`orders.bill_serial_number`** (text, unique), NOT `orders.id`.
- `orders.status` = kitchen/delivery progress. `payment_status` = money. Never confuse them.
- `orders` was already in `supabase_realtime` — a bare `ADD TABLE` aborts migrations.
- `rider_deliveries()` had to be DROPped and recreated to add columns (Postgres refuses
  in-place return-type changes). Done inside one transaction; grants re-applied.
- `payments` status CHECK had to be **swapped** — `create table if not exists` is a
  silent no-op when the table exists, so the old 3-value CHECK survived and would have
  rejected `double_paid`.
- All three discount functions **rewrite `orders.total`**, so `payfast-token` charges
  the discounted amount. Verified by reading `redeem_voucher`, `redeem_loyalty_points`
  and `apply_first_order_discount`.

### Edge Functions — both deployed and tested

| Function | JWT | Tests |
|---|---|---|
| `payfast-token` | **on** | 4/4 — real token, 2 baskets, 404 other user's order, 409 already paid |
| `payfast-ipn` | **off** | 6/6 — see below |

`scripts/fake_ipn.ts` sends simulated IPNs. Reads `PAYFAST_SECURED_KEY` /
`PAYFAST_MERCHANT_ID` from the **environment**, never from a file.

```
10:55:14  info    IPN … 000 paid                    (a)
10:55:35  info    IPN … 000 duplicate               (b)
10:55:38  warning IPN rejected: hash mismatch      (c) HTTP 400
10:55:48  error   IPN needs manual review: amount_mismatch   (d)
10:55:49  info    IPN … 002 failed                  (e1)
10:55:51  info    IPN … 000 paid                    (e2)
10:56:00  info    IPN …k3h 000 paid                 (f1)
10:56:02  error   IPN needs manual review: double_paid        (f2)
```

Function logs: Supabase → Edge Functions → `payfast-ipn` → Logs.

### Checkout flow

```
Cart → Checkout → [ Continue with Payment ] → Payment page
                                                    │
                        ┌───────────────────────────┴──────────────┐
                        ↓                                          ↓
              Online Payment                            Cash on Delivery
              (order created for the token,             (order created)
               PayFast WebView opens)                           │
                        │                                       ↓
              ┌─────────┴─────────┐                     Order tracking ✅
        press X / back         pays                    Cash Collected (rider)
              ↓                 ↓
      ORDER DELETED       spinner "Confirming…"
      cart kept           wait ≤45s for IPN
      back to payment     → Order tracking ✅
      screen (loops)
```

**Nothing is written until a method is chosen.** Cancelling deletes the order, its
basket rows, the voucher claim and the branch alert. Cart and saving survive.

`discard_unpaid_order` **refuses** rather than deletes when the order isn't theirs, isn't
`payment_method = 'online'`, is already `paid`, or has a `paid`/`double_paid` basket. That
last check is the safety net if an IPN lands in the same second the customer cancels.

It also **gives the bill serial back** when it deletes an order, because checkout has to
insert the `orders` row before PayFast can read `orders.total` off it. It only does so when
the discarded order held the *newest* number (`last_number = <discarded number>`) and no live
order still holds that serial — otherwise two real orders could end up with the same bill
number. Migration `20261019090000_release_bill_serial_on_discard.sql` also brought the
Abbottabad counter back from 73 to 71, closing the two holes abandoned attempts had left.

**On IPN timeout the order is KEPT, not deleted.** Deleting an order that turns out to
have been paid is far worse than keeping one that wasn't.

### Security rules held throughout

| Rule | How |
|---|---|
| App never sends an amount | only `order_id` goes to `payfast-token` |
| Secured key never in Flutter | `PayfastWebView` pushed directly; `RedirectionService` abandoned entirely because `build()` requires `setSecuredKey` |
| Fresh basket every tap | no caching anywhere |
| SDK callbacks never mark paid | SnackBars only; only the IPN writes `payment_status` |
| URLs distinct | `/success` vs `/failure`, neither contains the other |
| Function grants | `apply_payment_result` → service_role only; `mark_cash_collected`, `rider_deliveries` → authenticated |

---

# 🔴 BLOCKER FOR PRODUCTION

```dart
// packages/payfast_flutter_sdk/lib/src/widgets/payfast_webview.dart:72
'&SIGNATURE=testsign'
```

The SDK hardcodes a **fake signature** on every transaction. PayFast's sandbox tolerates
it — which is why the test payment went through. **Live will almost certainly reject it.**

Vendor SDK bug. Needs the real formula from PayFast's engineer. This is the only thing
between the app and real money.

---

# ⚠️ Never tested on a device

| | Status |
|---|---|
| Cancel → rollback → back to payment screen | built, **not run** |
| COD path end to end | **not run** |
| Rider "Cash Collected" button | **not run** |

`adb devices` is empty, **0 AVDs, no system images**. Profile APKs are built and installable:

```bash
flutter build apk --profile && flutter install
```

`.env` is bundled as an asset and already contains every key, so **no `--dart-define` is
needed**. `PAYFAST_ENV=uat` lives in Supabase secrets, not the app, so UAT is guaranteed
whichever APK is installed.

---

# Remaining gaps

- 🔴 **`SIGNATURE=testsign`** — see above, blocks production
- **No "Pay now" on the order screen** for an unpaid online order. The cancel-loop covers
  the pre-payment case, but a customer whose IPN timed out has no retry path in-app.
- **Order tracking screen shows no payment status at all** — `grep payment` on it returns
  nothing, so a customer cannot see whether they paid.
- **No refund path** for `double_paid`. The endpoint exists in the vendor PHP
  (`PayFastApi::refundTransaction`). A `double_paid` basket is only logged for manual review.
- **`transactions` table is orphaned** — `payments` replaced it, nothing writes to it now.
- **Branch panel can't see payment state.** Needs the other dev:
  1. show `payment_method` + `payment_status` on branch orders
  2. a filter for **unpaid online** orders (customer abandoned)
  3. a **refund** button for `double_paid`

---

# 🔴 Pre-existing, unrelated, NOT fixed

**`orders`, `order_items`, `order_status_history`, `transactions`, `rider_assignments`,
`rider_details`, `branches` all have RLS DISABLED with zero policies** in `public`.
Confirmed via `pg_class.relrowsecurity` and an empty `pg_policies`.

With the publishable key that ships inside the APK, **anyone can read every customer's
orders (name, phone, address) and write to them.** This predates all payment work.

Also:
- **The kitchen starts on insert.** `orders` is inserted as `confirmed` and
  `trg_order_alerts_on_insert` fires immediately, so the branch is alerted before
  payment. For online orders this window is the length of the PayFast checkout. Accepted
  for v1; `awaiting_payment` is the proper fix but would need the other dev's panel to
  handle a new status value.
- `AGENTS.md` still describes **Safepay**. The gateway is **Premier PayFast**.
- `G:\ElectronApps\mrpizzshi\cred.md` holds a plaintext database password.
- `mrpizzshi/001_payments.sql` — the reference file — was **deleted** on request.
  Its content is now embodied in the migrations above.
- Nothing has been committed. The tree had uncommitted work before this chat started.

---

# Secrets

Set in Supabase (dashboard → Edge Functions → Secrets, or `npx supabase secrets set`):
`PAYFAST_MERCHANT_ID`, `PAYFAST_SECURED_KEY`, `PAYFAST_MERCHANT_NAME`, `PAYFAST_ENV`.

Values deliberately **not** written here. These are **UAT/sandbox** keys — no real money
at risk. When swapping in **live** keys, set them the same way and do not paste them into
chat or the repo.

Test account used for curl tests: `razashahzaib119@gmail.com` (32 orders, password in
chat history).

---

# Previous chat (2026-10-08 → 10-10) — `ses_ee4e6b8fbffeqjOPyJVPdH4cJ1`

### Favourites feature — DONE

Database-backed rather than in-app storage (was an in-memory `Set<String>`, lost on
restart, leaked between accounts on a shared phone).

- Migration applied: `public.favorites` + RLS, cascade on profile and menu item.
  Verified live — a spoofed insert under `role authenticated` was rejected.
- `favoritesProvider` is an `AsyncNotifier` keyed on `currentUserIdProvider`.
- Heart button on `PizzaCard` and `GridItemCard`; `FavoritesScreen` rewritten
  (loading state, `context.pop()`, image resolver); drawer count badge.
- **22 new tests.** `flutter analyze` clean.

### PayFast spec — `docs/superpowers/specs/2026-10-08-payfast-payment-design.md`

- Read `Merchant_Integration_Guide.pdf` v2.3 (2 Oct 2024, PayFast's own, CTO-reviewed).
- Audited `apps-payfast-…-magento-2-sandbox-plugin` — **PHP/Magento 2**, not a Flutter
  package, cannot be installed into this app. Clean, not malicious.
- **§12 still holds 7 unanswered questions** — sandbox credentials, sandbox URL
  confirmation, written confirmation the sandbox cannot move real money.
