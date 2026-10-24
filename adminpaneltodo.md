# Admin Panel — Pickup Order Support

**Written:** 2026-10-19
**For:** the machine where the real admin panel lives.

> **The customer app and the database are already done and deployed.**
> This file is only about what the admin panel has to do.

---

## 1. What a pickup order is

A customer orders from the app, picks **Pickup** instead of Delivery, and chooses
to collect it from a branch themselves.

| | Delivery | Pickup |
|---|---|---|
| `orders.order_type` | `'delivery'` | `'pickup'` |
| `orders.address_id` | set | `null` |
| `orders.delivery_address` | the address | empty |
| `orders.delivery_charges` | branch fee | `0` |
| Rider | yes | **never** |
| Collected by | a rider, at the door | the customer, at the counter |
| `payment_method` | `'online'` or `'cod'` | `'online'` or `'cod'` |

The app has been able to place pickup orders for a long time. Nothing downstream
ever used `order_type`, so those orders would have been cooked and then described
to the customer as "waiting for a rider". That part is fixed.

---

## 2. The status flow

Pickup orders use **four** of the six statuses that already exist. **No new status
was added** — `delivered` is reused to mean *collected*, because the loyalty
trigger already fires on `delivered` and every consumer of `orders.status`
already understands it.

| # | Status stored | What the customer sees in the app |
|---|---|---|
| 1 | `confirmed` | Order received |
| 2 | `in_kitchen` | Preparing your food |
| 3 | `ready_for_pickup` | **Ready to Collect!** |
| 4 | `delivered` | **Collected!** |

`out_for_delivery` is **never** used by a pickup order. The database now refuses
to set it (see §4).

---

## 3. What already exists in the database — do not rebuild

### `collect_pickup_order(p_order_id uuid)` → returns the order row

The one button that closes out a pickup order. It does **all three** in a single
statement:

- sets `status = 'delivered'`
- for a cash order, sets `payment_status = 'paid'`
- writes `order_status_history` so the customer's timeline updates

Call it with:

```js
const { data, error } = await supabase.rpc('collect_pickup_order', {
  p_order_id: orderId,
});
```

It refuses, with a message you can show the user, when:

| Message | Why |
|---|---|
| `Only branch staff can collect a pickup order` | caller is not branch staff or owner |
| `That order belongs to another branch` | wrong branch |
| `This is a delivery order. A rider completes it instead.` | it isn't a pickup order |
| `This order was cancelled` | already cancelled |
| `This order has already been collected` | already done |
| `This order has not been paid. Check the PayFast payment before collecting it.` | online order whose PayFast IPN hasn't landed |

That last one is deliberate. An online order is only ever marked paid by PayFast's
own webhook, so the panel must not hand over food against a payment that never
arrived. If it fires, wait and retry — the IPN is usually seconds behind.

---

## 4. Two guards the database now enforces

You do not need to code around these, but you **will** hit them if you still try
to put pickup orders through the rider flow. Both raise a clear error.

**A pickup order cannot be set to `out_for_delivery`:**

> `Order <id> is a pickup order. It is collected at the counter, never sent out for delivery.`

**A rider cannot be assigned to a pickup order:**

> `Order <id> is a pickup order. It has no rider and no delivery address.`

---

## 5. Changes the admin panel needs

### 5.1 Show pickup orders separately

Right now a pickup order and a delivery order look identical on the board — same
columns, same rider assignment, same buttons. Separate them.

Filter on `order_type`. If you read through an RPC, note that `my_orders()` and
`order_tracking()` already return `order_type`.

Suggested layout: pickup orders in their own **COUNTER** column, showing the branch
name instead of an address, with no rider controls at all.

### 5.2 Hide the rider controls for pickup orders

Any "Assign Rider" button should not render for `order_type === 'pickup'`. The
database will block the insert anyway, but a button that always fails is worse
than no button.

### 5.3 The final button

On a pickup order in `ready_for_pickup`, the action is:

```
Collected & Paid
```

One call to `collect_pickup_order`. Do **not** implement it as "set status to
delivered, then separately mark cash collected" — that two-step version is
exactly the bug this work removed. It is how a shop ends up taking cash at the
counter that the ledger still says is owed.

### 5.4 Write every status move to `order_status_history`

**This one is easy to miss and it breaks the customer's timeline.**

Nothing currently writes that table except the rider functions. A pickup order
has no rider, so unless the panel inserts the row itself, the customer's tracking
screen shows the current status but an **empty history list**.

After each status change:

```js
await supabase.from('order_status_history').insert({
  order_id: orderId,
  status: newStatus,     // e.g. 'in_kitchen'
  changed_by: staffUserId,
});
```

`collect_pickup_order` already does this for the final step — do not double-insert
`delivered` yourself.

### 5.5 Use the word "Collected", not "Delivered"

For a pickup order, `delivered` means the customer took the food away. Label the
column **Collected**. The app already says "Collected!" — if the panel says
"Delivered" for the same order the two screens disagree in front of the customer.

---

## 6. Real column names on `orders`

Verified against the live database. Several of these have different names than
you might expect, and a wrong name silently yields `null` rather than an error.

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | primary key |
| `bill_serial_number` | text | **not** `bill_number`, **not** `token_number` |
| `customer_id` | uuid | the app's user |
| `branch_id` | uuid | **required**, every order has one |
| `address_id` | uuid | `null` for pickup |
| `order_type` | text | `'delivery'` or `'pickup'` |
| `status` | text | **not** `stage` |
| `cancel_reason` | text | |
| `subtotal` / `tax` / `total` | numeric | |
| `delivery_charges` | numeric | **not** `delivery_fee`; `0` for pickup |
| `discount_amount` | numeric | **not** `discount` |
| `discount_amount_source` | text | |
| `customer_name` / `customer_phone` | text | frozen at checkout |
| `delivery_address` | text | **not** `address`; empty for pickup |
| `delivery_latitude` / `delivery_longitude` | numeric | `null` for pickup |
| `rider_id` / `rider_name` / `rider_phone` | | `null` for pickup |
| `status_changed_at` | timestamptz | maintained by trigger |
| `payment_status` | text | `pending` / `paid` / `failed` |
| `payment_method` | text | `cod` / `online` |

`order_items` — the columns are **`id`, `order_id`, `menu_item_id`, `quantity`,
`price_at_order`**. There is no `name`, no `qty` and no `price` on this table;
the item name lives on `menu_items` and needs a join:

```js
const { data } = await supabase
  .from('order_items')
  .select('quantity, price_at_order, menu_items(name, image_url)');
```

---

## 7. Test checklist

Run this once on a real device before shipping.

- [ ] Place a **cash pickup** order in the app. It appears in the counter board.
- [ ] Move it: `confirmed` → `in_kitchen` → `ready_for_pickup`. The app updates
      live on each move, and the customer's timeline fills in (this is the check
      for §5.4).
- [ ] The app says **"Ready to Collect!"** and names the branch — no rider
      mentioned anywhere.
- [ ] Press **Collected & Paid**. One click. Status becomes `delivered`,
      `payment_status` becomes `paid`.
- [ ] The app shows **"Collected!"**. Loyalty points land.
- [ ] Try the same with an **online pickup** order: it appears, moves, and the
      final button refuses until PayFast's IPN has landed.
- [ ] Confirm a **delivery** order is unaffected end to end, rider included.
- [ ] Confirm no "Assign Rider" button renders on a pickup order.

---

## 8. Reference — migrations that made this possible

Both are already applied to the database.

| Migration | What it did |
|---|---|
| `20261019093000_pickup_collect_and_rider_guards.sql` | `collect_pickup_order()`, plus the two guards |
| `20261019090000_release_bill_serial_on_discard.sql` | bill serial given back when an abandoned payment is discarded |