# PayFast Payment Integration - Design

**Status: SPECIFICATION ONLY. Nothing in this document has been implemented.** No
database migration has been applied. No Edge Function has been written or deployed. No
Dart file has been added. This document exists so the wire protocol can be checked
against PayFast's own materials before a single line of code is written.

> **Gateway correction.** `AGENTS.md` currently describes **Safepay** as the payment
> gateway. The gateway for this project is **Premier PayFast**. The Safepay section of
> `AGENTS.md` is stale and should be replaced — see §13.

## 1. Problem

MrPizza can place an order, apply a voucher, and spend loyalty points, but it cannot take
money. There is no payment path of any kind:

- `grep -ri "safepay\|payfast" lib/` → **no matches**
- `supabase/functions/` → **does not exist on disk**
- Deployed Edge Functions → only `create-rider-account`

A customer confirms an order and it sits in the database with no way to settle it. The
gateway was chosen and merchant onboarding is under review, with sandbox access granted in
the meantime, so the protocol can be built and tested before production credentials exist.

## 2. Sources of truth

Two documents were supplied. They are not equal in authority and this spec follows the
higher one.

| Source | Version | Authority |
|---|---|---|
| `Merchant_Integration_Guide.pdf` (PayFast) | v2.3, 2 Oct 2024 | **Authoritative.** Written by PayFast's own engineers, reviewed by their CTO. |
| `apps-payfast-…-magento-2-sandbox-plugin` | 2022 | **Reference only.** Third-party, PHP/Magento 2. |

The Magento plugin is *not* a Flutter or Dart package and cannot be installed into this
app. It is PHP bound to `Magento\Sales\Model\Order`, `InvoiceService`, `Checkout\Model\Session`
and Magento layout XML. Its value is that it demonstrates a working integration of the same
gateway, so its protocol details are cross-checked against the guide below. Every protocol
claim in this spec is taken from the guide, and the plugin is cited only where the two
disagree — see §11.

The plugin was audited before being read for anything else: three URLs in the entire package
(the XML namespace and two PayFast hosts), no obfuscation, no `eval` / `base64_decode` /
`shell_exec` / `system` / `proc_open`, and no hardcoded credentials. It is not malicious.
It is simply old and written for another platform.

## 3. Goals

- A customer can pay for an order from the app, in sandbox first and production later.
- **An order is marked paid only from PayFast's backend notification.** A browser
  redirect alone never marks anything paid.
- The amount PayFast reports as charged is compared against the amount stored on our order
  row before anything is marked paid.
- A repeated, delayed or duplicated notification can never mark an order paid twice.
- `MERCHANT_ID`, `SECURED_KEY` and every other secret live only in Edge Function
  environment variables. No secret is ever compiled into the APK.
- A tampered phone cannot invent a payment, change an amount, or mark its own order paid.
- Refunds are supported once PayFast supplies refund documentation (§12).

## 4. Non-goals

Deliberately excluded from v1:

- **Refunds.** Guide v2.3 documents checkout only. The 2022 plugin references a refund API
  on a different host (`apipxyuat.apps.net.pk:8443/api`) that the current guide does not
  describe. Building against an undocumented, undated endpoint for real money is not
  acceptable, so refunds wait for PayFast's refund document. See §12.
- **Tokenised recurring payments.** `RECURRING_TXN`, `PROCESSING_TYPE = HYBRID_TOKEN` and
  `INSTRUMENT_TOKEN` appear in the guide but are irrelevant to one-off food orders.
- **I-frame checkout.** The guide's preface claims coverage of "Hosted Checkout and I-frame
  based transactions", but the table of contents documents only the hosted Form POST
  redirect flow. We build that one.
- **Multi-currency.** `CURRENCY_CODE` is `PKR`. MrPizza prices in PKR only.
- **The Magento plugin's five payment sub-methods** (`payfast_account`, `payfast_wallet`,
  `payfast_card`, `payfast_upicard`, `payfast`). PayFast decides the instrument; we send
  `Transaction_Instrument` only if we ever need to restrict it.
- **A branch→`STORE_ID` mapping.** `STORE_ID` is supported by the API (§7) but wired to a
  branch only when PayFast confirms which outlet ids belong to Abbottabad and Mansehra.

## 5. Payment flow

### 5.1 Outbound — starting a payment

```
Customer app                Edge Function                PayFast
     |                            |                         |
     |  1. place order           |                         |
     |  POST /payfast-create-transaction                     |
     |---------------------------->|                         |
     |                             | 2. read order total     |
     |                             |    from our own DB      |
     |                             |    (never from client)  |
     |                             |                         |
     |                             | 3. POST GetAccessToken  |
     |                             |    MERCHANT_ID,          |
     |                             |    SECURED_KEY,          |
     |                             |    BASKET_ID, TXNAMT,    |
     |                             |    CURRENCY_CODE         |
     |                             |------------------------>|
     |                             |  ACCESS_TOKEN           |
     |                             |<------------------------|
     |                             |                         |
     |  4. return the form fields|                         |
     |<----------------------------|                         |
     |                                                         |
     |  5. open PayFast hosted page (browser / custom tab)   |
     |-------------------------------------------------------->
     |                                                         |
     |                              customer pays (OTP etc.)   |
     |                                                         |
     |  6. browser returns to app deep link                   |
     |<--------------------------------------------------------
     |                            (screen refreshes only)
```

Steps 1–4 happen in the Edge Function. Step 5 is a browser. Step 6 is **not** trusted.

### 5.2 Inbound — the payment notification

```
PayFast                     Edge Function                  Our database
    |                            |                             |
    |  GET /payfast-ipn?...      |                             |
    |  (CHECKOUT_URL callback)   |                             |
    |--------------------------->|                             |
    |                            | 1. verify validation_hash   |
    |                            |    (timing-safe)            |
    |                            |                             |
    |                            | 2. err_code in {000, 00}?  |
    |                            |                             |
    |                            | 3. transaction_amount ==   |
    |                            |    order total?            |
    |                            |                             |
    |                            | 4. insert-or-ignore on     |
    |                            |    unique transaction_id   |
    |                            |---------------------------->|
    |                            |                             |
    |                            | 5. mark order paid         |
    |                            |---------------------------->|
    |  200 OK (fast)             |                             |
    |<---------------------------|                             |
```

PayFast may push this **immediately or after a delay** (guide p12), so the function must be
fast and must tolerate arriving late, twice, or out of order.

## 6. Getting an access token

| | |
|---|---|
| **URL** | `https://ipguat.apps.net.pk/Ecommerce/api/Transaction/GetAccessToken` |
| **Method** | `POST` |
| **Content type** | `application/x-www-form-urlencoded` |

Request fields — **all mandatory** (guide p11):

| Field | Source of the value |
|---|---|
| `MERCHANT_ID` | Edge Function secret |
| `SECURED_KEY` | Edge Function secret |
| `BASKET_ID` | Our `orders.id`, as text |
| `TXNAMT` | The order total read from our database |
| `CURRENCY_CODE` | `PKR` |

Response:

```json
{
  "MERCHANT_ID": "…",
  "ACCESS_TOKEN": "…",
  "NAME": "…",
  "GENERATED_DATE_TIME": "…"
}
```

Two guide details that are easy to miss and will break the call if ignored:

- **"Empty user agents are not allowed"** (guide p10). Every request must carry a real
  `User-Agent`. An unset or empty header is rejected.
- **The token is bound to the basket and the amount.** Guide p12 states `TXNAMT` and
  `BASKET_ID` "should match with" what was sent to the token API. A token minted for a
  Rs.500 order therefore cannot be presented to collect a different amount. This is a real
  integrity control provided by PayFast, and it is why the token is fetched **after** the
  order row exists — never before, and never with a client-supplied amount.

## 7. Initiating the transaction (Form POST)

| | |
|---|---|
| **URL** | `https://ipguat.apps.net.pk/Ecommerce/api/Transaction/PostTransaction` |
| **Method** | `POST` (`application/x-www-form-urlencoded`) |

The Edge Function returns these values to the app, which renders them as a form and submits
it to PayFast, exactly as guide p17–18 does in its PHP example.

**Mandatory** (guide p21):

| Field | Value we send |
|---|---|
| `MERCHANT_ID` | merchant id (public identifier, not a secret) |
| `MERCHANT_NAME` | `MrPizza` |
| `TOKEN` | from §6 |
| `PROCCODE` | `00` |
| `TXNAMT` | order total from our database |
| `CUSTOMER_MOBILE_NO` | order phone |
| `CUSTOMER_EMAIL_ADDRESS` | `profiles.email` |
| `SIGNATURE` | any non-empty string — the guide calls it "a random string value" |
| `VERSION` | any non-empty string — same |
| `TXNDESC` | short description of the order |
| `SUCCESS_URL` | deep link back into the app |
| `FAILURE_URL` | deep link back into the app |
| `BASKET_ID` | `orders.id` as text |
| `ORDER_DATE` | order date, `YYYY-MM-DD` |
| `CHECKOUT_URL` | **the `payfast-ipn` Edge Function URL** — see §9 |

**Optional, sent where useful** (guide p12–14): `CURRENCY_CODE=PKR`, `TRAN_TYPE=ECOMM_PURCHASE`,
`STORE_ID`, `CUSTOMER_NAME`, `COUNTRY=PK`, `MERCHANT_CUSTOMER_ID` (our `profiles.id`),
`SHIPPING_*` and `BILLING_*` from the saved address, `ITEMS[n][SKU|NAME|PRICE|QTY]`.

`SIGNATURE` and `VERSION` are documented as arbitrary strings and carry no security meaning.
They exist so PayFast can identify which integration shape is calling.

## 8. The notification (redirect / IPN)

| | |
|---|---|
| **URL** | our `payfast-ipn` Edge Function, wired as `CHECKOUT_URL` |
| **Method** | `GET` with query parameters (guide p19, Table 1.2) |

| Field | Meaning (guide p19–21) |
|---|---|
| `transaction_id` | PayFast's transaction id |
| `err_code` | `000` or `00` = success |
| `err_msg` | failure description |
| `basket_id` | the order id we sent |
| `order_date` | date we sent |
| `validation_hash` | see §9 |
| `transaction_amount` | **amount PayFast actually charged** |
| `merchant_amount` | amount we sent |
| `discounted_amount` | discount we applied, if any |
| `transaction_currency` | `PKR` |
| `PaymentName` | `account`, `card`, `wallet` |
| `Instrument_token`, `Recurring_txn` | optional services we do not use |

`transaction_amount` and `merchant_amount` are separate fields by design. Their difference is
the signal for §10.3.

## 9. `validation_hash`

```
validation_hash = SHA256( "<basket_id>|<secured_key>|<merchant_id>|<err_code>" )
```

The `|` separator is part of the string and must not be trimmed. Order matters.

Verified against the guide's own published test vector (guide p20):

```
input : BAS-01|jdnkaabcks|102|000
sha256: e8192a7554dd699975adf39619c703a492392edf5e416a61e183866ecdf6a2a2
guide : e8192a7554dd699975adf39619c703a492392edf5e416a61e183866ecdf6a2a2
match : yes
```

This vector becomes a unit test. If our implementation reproduces it, the string
construction is correct.

**This must be compared with a constant-time comparison.** A plain `==` leaks timing
information about the expected hash, byte by byte. See §11.

## 10. Security rules this implementation will enforce

### 10.1 Only the backend notification marks an order paid

`CHECKOUT_URL` is defined by PayFast as the URL that "payment information or notification is
pushed to the merchant at the backend" (guide p12). `SUCCESS_URL` and `FAILURE_URL` are
where the **customer's browser** is redirected. A browser is under the customer's control:
it can be closed, never fire, replay an old URL, or be scripted.

Therefore:

- `payfast-ipn` is the **only** writer of the paid state.
- The deep link back into the app **only refreshes** the order screen.
- The app must not display "paid" because a redirect said so. It asks the database.

### 10.2 The hash is verified before anything is parsed or trusted

`validation_hash` is checked with a constant-time comparison, against the `basket_id` and
`err_code` **as received**. A failed check returns `400` and writes nothing.

### 10.3 The amount PayFast charged is compared to our stored total

Before marking paid:

- `transaction_amount` must equal the order's stored total.
- `transaction_currency` must be `PKR`.
- `merchant_amount` must equal the stored total, unless a discount was applied, in which
  case it must equal total − discount.

A mismatch **marks the transaction for review and does not mark the order paid.** It is
logged and alerted. `AGENTS.md` requires this check; the reference plugin does not perform
it, which is one reason we do not copy the plugin.

### 10.4 Replays and duplicates cannot double-apply

Three independent guards:

1. `unique (gateway, transaction_id)` — the same PayFast transaction can only be recorded
   once.
2. `unique (order_id) where status = 'paid'` — an order can only be paid once, no matter how
   many notifications arrive.
3. An explicit status guard: a notification for an order already `paid` is acknowledged and
   ignored, not re-applied.

The guide's hash covers `basket_id` but no timestamp, so it gives us **no** replay window by
itself. Idempotency is ours to build.

### 10.5 Secrets never reach the app

`SECURED_KEY` and `MERCHANT_ID` live in Edge Function environment variables only. They are
never in `.env` that ships with the APK, never in Dart source, never in a log line.

An APK is a ZIP file. Anything in it can be read by anyone holding the phone. A `SECURED_KEY`
in the app is a `SECURED_KEY` in an attacker's hands.

### 10.6 The amount is never taken from the client

`payfast-create-transaction` reads the total from the `orders` row. It ignores any amount in
the request body. A tampered app asking for a Rs.1 payment gets a token for the real total.

### 10.7 `verify_jwt: false` on the notification function — deliberately

PayFast cannot present a Supabase JWT, so the function must be reachable without one. That
makes §10.2–§10.4 the entire defence, which is exactly why they are not optional. Nothing
else may be reachable from this endpoint.

## 11. Where we deliberately differ from the Magento plugin

| Plugin behaviour | Problem | What we do instead |
|---|---|---|
| `return $hash == $validation_hash;` | Non-constant-time comparison leaks the hash by timing | Constant-time comparison |
| `if ($errorCode == '000')` | The guide lists **`000` and `00`** as both successful (p22). A `00` success is recorded as a **failure** | Accept `000` and `00` |
| Browser redirect and IPN treated identically | The browser is user-controlled | Only the backend notification marks paid (§10.1) |
| `transaction_amount` logged but never compared | An amount mismatch is never detected | Compare against the stored total (§10.3) |
| Order marked paid on hash + `err_code` alone | No replay protection; nothing binds a notification to a time | Unique constraints + status guard (§10.4) |
| Token fetched in a layout block before the order is saved | Token and order can disagree | Token fetched after the order exists (§10.2) |
| Loose `==` on `err_code` and amounts | `0` and `'000'` compare equal | Strict typed comparison after parsing |

The plugin is not dangerous. It is a 2022 Magento integration that predates the checks this
project's own rules require. It is a useful protocol reference and a poor security template.

## 12. Open questions blocking implementation

These must be answered before code is written. Items 1–3 are hard blockers.

1. **Sandbox credentials.** `MERCHANT_ID`, `SECURED_KEY`, and `STORE_ID` if one was issued.
   The guide's own example values (`MERCHANT_ID=102`, `SECURED_KEY=zWHjBp2AlttNu1sK`) are
   PayFast's public documentation samples and are not ours.
2. **Sandbox base URL confirmation.** The guide uses `https://ipguat.apps.net.pk`. Is that
   the URL issued to us, or a different UAT host?
3. **Is the sandbox guaranteed to be test-only?** Until production credentials exist we need
   written confirmation that the sandbox cannot move real money.
4. **Refund API.** Not in guide v2.3. Request the current document. Until then no refund code
   is written.
5. **`STORE_ID`.** Optional, and validated if sent (guide p18, format like `102-ZEOJDZS3V`).
   Should Abbottabad and Mansehra each have one? If yes, which ids?
6. **Callback timing.** The guide offers `CHECKOUT_URL` as immediate or delayed. Which is our
   account configured for? Affects only how long the app waits before showing a final state.
7. **Notification delivery guarantees.** Does PayFast retry a notification it could not
   deliver? Affects whether the app needs an explicit "refresh payment status" action.

## 13. Proposed data layer — **NOT YET APPLIED**

Shown for review only. **No migration has been run.** Awaiting explicit approval.

```sql
create table public.payment_transactions (
  id                        uuid primary key default gen_random_uuid(),
  order_id                  uuid not null references public.orders(id) on delete cascade,
  user_id                   uuid not null references public.profiles(id) on delete cascade,
  gateway                   text not null default 'payfast',
  basket_id                 text not null,
  transaction_id            text,
  status                    text not null default 'initiated',
  txnamt                    numeric(12,2) not null,
  currency_code             text not null default 'PKR',
  payfast_err_code          text,
  payfast_err_msg           text,
  payfast_transaction_amount numeric(12,2),
  payfast_merchant_amount   numeric(12,2),
  payfast_discounted_amount numeric(12,2),
  payment_instrument        text,
  failure_reason            text,
  paid_at                   timestamptz,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);
```

Statuses: `initiated` → `redirected` → `paid` | `failed` | `expired`.

Constraints carrying the §10.4 guarantees:

```sql
-- One PayFast transaction, recorded once.
create unique index payment_transactions_transaction_id_key
  on public.payment_transactions (gateway, transaction_id)
  where transaction_id is not null;

-- An order can be paid exactly once, no matter how many notifications arrive.
create unique index payment_transactions_one_paid_per_order
  on public.payment_transactions (order_id)
  where status = 'paid';

create index payment_transactions_order_id_idx
  on public.payment_transactions (order_id);
```

RLS shape: customers may **select** their own rows only. There is deliberately **no**
insert, update or delete policy for `authenticated` — only the Edge Function's
`service_role` writes, so a tampered app cannot fabricate a payment row. Every other table in
this project grants customers write access somewhere; this one must not.

## 14. Proposed Edge Functions — **NOT YET WRITTEN**

| Function | JWT | Purpose |
|---|---|---|
| `payfast-create-transaction` | required | Reads the order total from the DB, fetches a token, returns form fields |
| `payfast-ipn` | **not** required | The §5.2 handler. Sole writer of the paid state |
| `payfast-refund` | required, staff only | Blocked until §12.4 is answered |

## 15. Proposed app-side changes

- A PayFast repository in `lib/features/payment/data/`, injectable `SupabaseClient` like
  `loyalty_repository.dart`, calling the Edge Functions.
- `url_launcher` opens the hosted checkout — already a dependency, no new package.
- A deep link returns the customer to `/orders/track`. It refreshes and nothing more (§10.1).
- Order status continues to update live via the existing `realtime_client` subscription.
- No secret is ever read by the app. The app never sees `SECURED_KEY`.

## 16. Test plan

Beyond the happy path, the tests that actually matter:

| Test | Expected |
|---|---|
| Documented hash vector `BAS-01\|jdnkaabcks\|102\|000` | Reproduces the published SHA256 |
| Modified hash | Rejected, nothing written |
| `err_code=000` and `err_code=00` | Both mark paid |
| `err_code=002` (timeout) | Recorded failed, order not paid |
| Same notification delivered twice | Paid once, one row |
| Old notification replayed against a re-created order | Refused by the paid-order index |
| `transaction_amount` lower than the order total | Refused, flagged for review |
| Wrong `transaction_currency` | Refused |
| Request body amount faked to 1 on create | Real order total used |
| Network drops the create call mid-flow | No orphan paid order |

## 17. What was verified, and what was not

**Verified:** the `validation_hash` formula against the guide's published vector; the plugin
is not malicious; the sandbox host matches between guide and plugin; no PayFast or Safepay
code exists in the app today.

**Not verified:** nothing has been sent to PayFast's servers. Every endpoint, field name and
behaviour above is read from the PDF, not observed. The first sandbox call will confirm or
contradict it, and §12.1–§12.3 must be answered before that call is made.
